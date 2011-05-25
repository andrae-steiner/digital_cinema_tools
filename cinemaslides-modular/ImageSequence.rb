module ImageSequence
  
  require 'Asset'
  require 'Logger'
  require 'ShellCommands'
  require 'OptParser'
  require 'tempfile'

  ShellCommands = ShellCommands::ShellCommands
  
  THUMBFILE_SUFFIX = ".jpg"
  

  class FileSequence
    attr_reader :framecount
    def initialize (dir, output_format, fps, starting_frame)
      @starting_frame = starting_frame
      @framecount = 1 + starting_frame
      @dir = dir
      @fps = fps
      @output_format = output_format
      @logger = Logger::Logger.instance
    end

    def next_file
      file = File.join( @dir, "#{ '%06d' % @framecount }.#{ @output_format }" )
      @framecount += 1
      file
    end
    
    def sequence_links_to( file, seconds )
    ( 1..( seconds * @fps - 1 ) ).each do # 1 file already written
      link = next_file
      # FIXME link available on all platforms?
#      @logger.debug("4 symlink p1 = #{ file }, p2 = #{ link }")
      File.symlink( File.expand_path(file),  link )
    end
    
  end


  end

  class ImageSequence
    attr_reader :asset_functions, :output_format, :fps, :conformdir
    def initialize (source, output_type_obj, output_format, resize,
                    fps, black_leader, black_tail, fade_in_time, duration, fade_out_time, 
                    crossfade_time)
      @imagecount = 0
      @imagecount_mutex = Mutex.new
      @conform_mutex = Mutex.new
      @source = source
      @logger = Logger::Logger.instance
      @output_type_obj = output_type_obj
      @output_format = output_format
      @fps = fps
      @black_leader = black_leader
      @black_tail = black_tail
      @fade_in_time = fade_in_time
      @duration = duration
      @fade_out_time = fade_out_time
      @crossfade_time = crossfade_time
      @conformdir =  output_type_obj.conformdir
      @file_sequence_trailer = FileSequence.new(output_type_obj.conformdir, output_format, @fps, 
                                                starting_frame = n_sequence_frames - @black_leader * @fps)
      @asset_functions = Asset::ImageAssetFunctions.new(output_type_obj, resize)
    end
    
    def self.n_of_images_ok?(source)
      TRUE
    end
        
    def framecount
      @file_sequence_trailer.framecount
    end
        
    def n_sequence_frames
      # FIXME raise some exception about an undefined method
      raise NotImplementedError, "Do not instanciate this abstract class: ImageSequence"
    end
          
    def n_image_sequence_frames
      # meat of sequence_frames (without black leader/tail) -- where audio will play
      n_sequence_frames - ( ( @black_leader + @black_tail ) * @fps )
    end
    
    def create_image_sequence
      create_leader(FileSequence.new(@conformdir, @output_format, @fps, 
                                                starting_frame = 0))
      
      create_transitions
      
      create_trailer(@file_sequence_trailer)
    end

    def create_montage_preview
      @thumb_asset_functions = Asset::ThumbAssetFunctions.new(@output_type_obj)
      Dir.mkdir( @output_type_obj.thumbsdir ) unless File.exists?( @output_type_obj.thumbsdir )
      @logger.info( "Create thumbnails" )
      thumbs = Array.new
      @source.each do |single_source|
	thumbasset, todo = @thumb_asset_functions.check_for_asset(single_source, THUMBFILE_SUFFIX)
	if todo
	  @logger.info( "Thumb for #{ single_source }" )
	  ShellCommands.IM_convert_thumb( single_source, @output_type_obj.thumbs_dimensions, thumbasset)
	end
	thumbs << thumbasset
      end
      thumbs = thumbs.join(' ')
      # cache montages, wacky-hacky using string of all thumbnail filenames (md5 hexdigest and some) to match
      thumbs_asset, todo =  @thumb_asset_functions.check_for_montage_asset(thumbs, THUMBFILE_SUFFIX )
      if todo
	ShellCommands.IM_montage(thumbs, @source.length, @output_type_obj.thumbs_dimensions, thumbs_asset)
      end
      return thumbs_asset
    end
    
    private 
    
    def lock_filename(f)
      f + "_lock"
    end
    
    def incr_imagecount
      @imagecount_mutex.synchronize do
	@imagecount += 1
      end
    end
    
    def get_imagecount
      @imagecount_mutex.synchronize do
	@imagecount
      end
    end

    def create_leader( file_sequence )
      # Create black leader
      if @black_leader > 0
        @logger.info( "Black leader: #{ @black_leader } seconds" )
	make_black_sequence( @black_leader, file_sequence )
      end
    end
    
    def create_transitions
      # FIXME raise some exception about an undefined method
      raise NotImplementedError, "Do not instanciate this abstract class: ImageSequence"
    end
    
    def create_trailer( file_sequence )
      # Create black tail
      if @black_tail > 0
        @logger.info( "Black tail: #{ @black_tail } seconds" )
	make_black_sequence(@black_tail, file_sequence )
      end
    end

    
    def fade_in_hold_fade_out( image, fade_in_time, duration, fade_out_time, file_sequence )
      if fade_in_time > 0
	fade_in( image, fade_in_time, file_sequence )
      end
      if duration > 0
	full_level( image, duration, file_sequence )
      end
      if fade_out_time > 0
	fade_out( image, fade_out_time, file_sequence )
      end
    end


    def fade_in( image, fade_in_time, file_sequence )
      @logger.info( ">>> Fade in #{ imagecount_info( image ) }" )
      initial = -100.0
      final = 0.0
      step = 100 / ( fade_in_time * @fps )
      fade( image, fade_in_time, initial, final, step, file_sequence )
    end


    def fade_out( image, fade_out_time, file_sequence )
      @logger.info( "<<< Fade out #{ imagecount_info( image ) }" )
      initial = 0.0
      final = -100.0
      step = - ( 100 / ( fade_out_time * @fps ) )
      fade( image, fade_out_time, initial, final, step, file_sequence )
    end

    def composite( image1, level, image2, output ) # -compress none for kakadu
      ShellCommands.IM_composite_command( image1, level, image2, @output_type_obj.depth_parameter, @output_type_obj.compress_parameter, output)
    end

    def fade( image, seconds, initial, final, step, file_sequence )
      if step > 0 # fade in
	ladder = ( initial .. final ).step( step ).collect
      else # fade out
	ladder = ( final .. initial ).step( step.abs ).collect
      end
      ladder[ -1 ] = 0 # sic. float implementation, tighten the nut
      levels = ladder.collect { |rung| sigmoid( rung, initial, final, -50, 0.125 ) }
      if levels.first < -50
	levels[ 0 ] = -100
	levels[ -1 ] = 0
      else
	levels[ 0 ] = 0
	levels[ -1 ] = -100
      end
      @logger.debug( "levels: #{levels.inspect}" )
      #
      # levels has 1 element more than the number of steps provided by the following range
      # so the last element never gets applied -- 
      # hence the shifted fade symmetry (by 1 step).
      # 
      ( 1..( seconds * @fps ) ).each do |i|
	filename = file_sequence.next_file
	level = levels[ i - 1 ]
	@logger.cr( sprintf( '%.2f', level ) )
	asset, todo = @asset_functions.check_for_asset( image, @output_format, level )
	if todo
	  @output_type_obj.convert_apply_level( image, level, asset )
	end
#	@logger.debug("1  symlink p1 = #{ asset }, p2 = #{ filename }")
	File.symlink( File.expand_path(asset),  filename )
      end
    end

    def crossfade( image1, image2, seconds, file_sequence )
      @logger.info( "XXX Crossfade #{ imagecount_info( image1 ) }" )
      initial = 100.0
      final = 0.0
      step = - ( 100 / ( seconds * @fps ) )
      ladder = ( final .. initial ).step( step.abs ).collect
      levels = ladder.collect { |rung| sigmoid( rung, initial, final, 50, 0.125 ) }
      ( 1..( seconds * @fps ) ).each do |i|
	filename = file_sequence.next_file
	level = levels[ i - 1 ]
	@logger.cr( sprintf( '%.2f', level ) )
	asset, todo = @asset_functions.check_for_asset( [ image1, image2 ], @output_format, level )
	if todo
	  composite( image1, level, image2, asset )
	end
#	@logger.debug("2 symlink p1 = #{ asset }, p2 = #{ filename }")
	File.symlink( File.expand_path(asset),  filename )
      end
    end

    def full_level( image, duration, file_sequence )
      @logger.info( "--- Full level #{ imagecount_info( image ) }" )
      level = 0
      file = file_sequence.next_file
#	@logger.debug("3 symlink p1 = #{ image }, p2 = #{ file }")
      File.symlink( File.expand_path(image),  file )
      if ( 1 ..( duration * @fps - 1 ) ).none? # only 1 image needed
  #      @framecount += 1 # temporary fix for FIXME @framecount stumble (Errno::EEXIST) on first fade out frame with 0 or 1 frame full level settings, like with $ cinemaslides 01.jpg 02.jpg -x crossfade,1,0
	@logger.debug( "Skip sequence links: Only 1 image needed here" )
      else
  #      @framecount += 1
	file_sequence.sequence_links_to( file, duration )
      end
    end
        
    # all fade/crossfade ops are based on these assets
    def conform( image )
      @logger.info( "Conform image: #{ image }" )
      asset, todo = @asset_functions.check_for_asset( image, @output_format )
      @logger.info( "Conform image: #{ image }, asset = #{ asset }, TODO = #{ todo}" )
      if todo
	File.open(lock_filename( asset ) , 'w') do |f2| 
	end
	@output_type_obj.convert_resize_extent_color_specs( image, asset  )
	begin
	  File.delete( lock_filename( asset ) )
	rescue
	end
      end
      first = true
      while (File.exists?( lock_filename( asset ) ) ) do
	if (first)
	      @logger.info( "Conform image: #{ image }, asset = #{ asset }, TODO = #{ todo} wait for unlock" )
	      first = false
	end
      end
      return asset
    end

    def make_black_frame( filename )
      asset, todo = @asset_functions.check_for_black_asset( @output_format )
      @output_type_obj.create_blackframe(asset) if todo
#      @logger.debug("0 symlink p1 = #{ asset }, p2 = #{ filename }")
      File.symlink(  File.expand_path(asset), filename )
    end

    def make_black_sequence( duration , file_sequence)
      if (duration < 1) 
	return
      end
      blackfile = file_sequence.next_file
      make_black_frame( blackfile )
      file_sequence.sequence_links_to( blackfile, duration )
    end
    
    def s_sign( value )
      return ( value.to_f / value.to_f.abs ).to_i
    end
    
    def sigmoid( value, initial, final, center, rate )
      if initial > final
	base = final
      else
	base = initial
      end
      return ( initial - final ).abs / ( 1.0 + Math.exp( rate * s_sign( final - initial ) * ( -( value - center ).to_f ) ) ) + base
    end
    
    def imagecount_info( image )
      "(#{ get_imagecount } of #{ @source.length })"
    end
    
    # calculate indices of source for multithreading
    def get_indices
      n_threads = OptParser::Optparser.get_options.n_threads
      indices = Array.new
      n_elements = @source.length/n_threads
      remainder = @source.length%n_threads
      if (n_elements == 0) 
	remainder.times do |i|
	  indices << [i,i]
	end
      else
	len2 = @source.length+n_threads-1
	(n_threads-remainder).times do |i|
	  start_index = i*len2/n_threads
	  end_index   = (i == (n_threads - 1)) ? @source.length - 1 : (i + 1)*len2/n_threads - 1
	  indices << [start_index, end_index]
	end
	remainder.times do |i|
	  f = i + n_threads-remainder
	  start_index = f*(len2)/n_threads - i
	  end_index   = (f == (n_threads - 1)) ? @source.length - 1 : (f + 1)*len2/n_threads - 1 - (i + 1)
	  indices << [start_index, end_index]
	end
      end
      return indices
    end


  end # ImageSequence

  class FadeOrCutTransitionsImageSequence < ImageSequence
            
    def create_transitions
      threads = Array.new
      indices = get_indices
      # start the threads
      indices.length.times do |i|
	start_index, end_index = indices[i]
	file_sequence = FileSequence.new(@conformdir, @output_format, @fps, 
                                                starting_frame = (@black_leader + start_index * ( @fade_in_time + @duration + @fade_out_time ) ) * @fps)
        threads << Thread.new do
	  @logger.debug("START CREATE_TRANSITIONS THREAD")
	  @source[start_index..end_index].each do |source_element|
	    incr_imagecount()
	    image = conform( source_element )
	    fade_in_hold_fade_out( image, @fade_in_time, @duration, @fade_out_time, file_sequence )
	  end
	end  #       Thread.new do
      end # indices.length.times do |i|
      threads.each do |t|
          t.join()
      end                            
    end
    
    def create_transitions_single_thread
      # Process all images
      file_sequence = FileSequence.new(@conformdir, @output_format, @fps, 
                                                starting_frame = ( @black_leader ) * @fps)
      @source.each_index do |index|
	incr_imagecount()
	image = conform( @source[ index  ] )
	fade_in_hold_fade_out( image, @fade_in_time, @duration, @fade_out_time, file_sequence )
      end
    end
    
    def n_sequence_frames
      ( ( @black_leader + @black_tail ) + @source.length * ( @fade_in_time + @duration + @fade_out_time ) ) * @fps
    end

  end

  class CrossfadeTransitionsImageSequence < ImageSequence
    
    def self.n_of_images_ok?(source)
      if source.length <= 1
	@logger.warn( "Can't crossfade less than 2 images (#{ source.first })" )
	@logger.info( "Either supply more than 1 image or change transition_and_timing to fade specs ('-x fade,a,b,c')" )
      end
      return source.length > 1
    end
    
    def create_transitions
      threads = Array.new
      indices = get_indices
      # start the threads
      indices.length.times do |thread_i|
	start_index, end_index = indices[thread_i]
	file_sequence = FileSequence.new(@conformdir, @output_format, @fps, 
                                                starting_frame = (@black_leader + start_index * ( @crossfade_time + @duration ) ) * @fps)
        threads << Thread.new do
	  @logger.debug("START CREATE_TRANSITIONS THREAD")
	  keeper = conform( @source[ start_index ] ) # keep a conform for the next crossfade (2nd will be 1st then, don't conform again)
	  count = end_index - start_index + 1
	  count = count - 1 if (thread_i == indices.length - 1) 
	  count.times do |index|
	    incr_imagecount()
	    image1 = keeper
	    image2 = conform( @source[ start_index + index + 1 ] )
	    keeper = image2
	    full_level( image1,  @duration, file_sequence )
	    crossfade( image1, image2,  @crossfade_time, file_sequence )
	  end
	  if (thread_i == indices.length - 1)
	    full_level( keeper,  @duration, file_sequence )
	  end
	end  #       Thread.new do
      end # indices.length.times do |thread_i|
      threads.each do |t|
          t.join()
      end                            
    end

    
    def create_transitions_single_thread
      # Process all images

      file_sequence = FileSequence.new(@conformdir, @output_format, @fps, 
                                                starting_frame = ( @black_leader ) * @fps)
      keeper = conform( @source[ 0 ] ) # keep a conform for the next crossfade (2nd will be 1st then, don't conform again)
      (@source.size - 1).times do |index|
	incr_imagecount()
	image1 = keeper
	image2 = conform( @source[ index + 1 ] )
	keeper = image2
	full_level( image1,  @duration, file_sequence )
	crossfade( image1, image2,  @crossfade_time, file_sequence )
      end
      # last image
      full_level( keeper,  @duration, file_sequence )
            
    end
        
    def n_sequence_frames
      
# Wrong      
#      ( ( @black_leader + @black_tail ) + @crossfade_time + @source.length * ( @crossfade_time + @duration ) ) * @fps 
      
      # implicit fade in/out first/last when crossfading
      
      # Wolfgangs commit 7f441cbc7edd1ba411bd
      ( ( @black_leader + @black_tail ) + ( ( @source.length - 1 ) * @crossfade_time ) + @source.length * @duration ) * @fps
      
    end
  end
  
  
  # Bildübergänge lassen sich leicht ändern und erweitern andrae.steiner@liwest.at
  class CrossfadeRotateTransitionsImageSequence < CrossfadeTransitionsImageSequence

    private 
    
    def crossfade( image1, image2, seconds, file_sequence )
      @logger.info( "XXX Crossfade #{ imagecount_info( image1 ) }" )
      initial = 100.0
      final = 0.0
      step = - ( 100 / ( seconds * @fps ) )
      ladder = ( final .. initial ).step( step.abs ).collect
      levels = ladder.collect { |rung| sigmoid( rung, initial, final, 50, 0.125 ) }
      ( 1..( seconds * @fps ) ).each do |i|
	filename = file_sequence.next_file
	level = levels[ i - 1 ]
	@logger.cr( sprintf( '%.2f', level ) )
	asset, todo = @asset_functions.check_for_asset( [ image1, image2 ], @output_format, level )
	if todo
	  composite( image1, i*15, level, image2, asset )
	end
#	@logger.debug("2 symlink p1 = #{ asset }, p2 = #{ filename }")
	File.symlink( File.expand_path(asset),  filename )
      end
    end

    
    def composite( image1, rotation, level, image2, output ) # -compress none for kakadu
      ShellCommands.IM_composite_rotate_command( image1, rotation, level, image2, @output_type_obj.depth_parameter, @output_type_obj.compress_parameter, output)
    end


  end



end