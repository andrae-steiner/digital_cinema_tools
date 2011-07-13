module InputType

  require 'Logger'
  require 'ShellCommands'
  require 'AudioSequence'
  require 'ImageSequence'
  require 'CinemaslidesCommon'
  
  ShellCommands = ShellCommands::ShellCommands
  
  class InputType
    def initialize (source, output_type_obj)
      @logger = Logger::Logger.instance
      @source = source
      @output_type_obj = output_type_obj
    end
    # seperates files into three categories
    # imagesequence, audio and files with no code delegate
    # and returns an array with arrays of these files
    # so if you want to use this class to seperate a videofile
    # with sound, this seperate function has to seperate the sound from the video
    # and to convert the video into an imagesequence.
    # Fading has to be set to cut and duration to 0.041666667.
    def seperate_and_check_files
      # seperate and check files
      # return [ [images], [audiofiles], [no_code_delagate_files] ]
      raise NotImplementedError, "Do not instanciate this abstract class: #{self.class}"
    end
  end
  
  # TODO this is just do show, that it is possible, nothing final
  class AVContainerInputType < InputType
    def initialize (source, output_type_obj, dont_check, dont_drop, audio_only, image_sequence_class)
      super( source, output_type_obj )
      @cinemaslidesdir = CSTools.get_cinemaslidesdir
      @options = OptParser::Optparser.get_options     
      @options.fade_in_time = 0
      @options.duration = 1.0/@options.fps
      @options.fade_out_time = 0
      @options.transition_and_timing = Array.new
      @options.transition_and_timing << CinemaslidesCommon::TRANSITION_CHOICE_CUT
      @options.transition_and_timing << @options.duration # duration
      # FIXME make as options on commandline
      @av_input_fps = ""
      @av_input_fps_option = ( @av_input_fps == "" ) ? "" : "-r #{ @av_input_fps }"
      @av_output_image_suffix = 'png'
      @asset_functions = Asset::AVSequenceAssetFunctions.new(output_type_obj, av_input_fps = @av_input_fps, av_output_image_suffix = @av_output_image_suffix )
    end
    def seperate_and_check_files
      if @source.empty?
	@logger.info( 'No files specified' )
	return Array.new, Array.new, Array.new, FALSE
      end
      if @source.length > 1
	@logger.info( 'Only one file allowed witn input-type avcontainer' )
	return @source, Array.new, Array.new, FALSE
      end
      @avfile = @source[0]
      
      image_asset_dir = @asset_functions.create_video_asset( @avfile ) {|asset_dir|
	Dir.mkdir( asset_dir )
	`ffmpeg -y -i #{CSTools.shell_escape(@avfile)} -an #{ @av_input_fps_option }   -qscale 1 -qmin 1 -intra  -pix_fmt yuv420p -b 50000k  #{File.join( asset_dir, CinemaslidesCommon::FILE_SEQUENCE_FORMAT + '.' + @av_output_image_suffix)}`
      }
      audio_asset = @asset_functions.create_audio_asset( @avfile ) {|a|
	`ffmpeg -y -i #{CSTools.shell_escape(@avfile)} -acodec pcm_s24le #{ @av_input_fps_option }  -ar 48000  #{ a }`
      }
      
      return Dir.glob( "#{ image_asset_dir }/*" ).sort,  [audio_asset], nil, TRUE
      
    end
  end

  class SlideshowInputType < InputType
    
    def initialize( source, output_type_obj, dont_check, dont_drop, audio_only, image_sequence_class  )
      super( source, nil )
      @dont_check = dont_check
      @dont_drop = dont_drop
      @audio_only = audio_only
      @image_sequence_class = image_sequence_class
    end
        
    def seperate_and_check_files 
      # check provided files for readability, type and validity
      # come up with 3 lists: image files, audio files, unusable files
#      @source = ARGV
      source_audio = Array.new
      if @dont_check ####
	if @source.empty?
	  @logger.info( 'No files specified' )
	  return @source, source_audio, Array.new, FALSE
	end
	# quick and dirty version of audio file pickup (which is the whole point of --dont-check)
	source_audio = Array.new	
	source_tmp,  not_readable_or_not_regular = collect_files( @source )
	@source = source_tmp.clone
	
	@source.each do |element|
	  if element =~ CinemaslidesCommon::AUDIOSUFFIX_REGEXP
	    source_audio << element
	    source_tmp.delete( element )
	  end
	end
	@source = source_tmp.clone
      else # check files
	# remove un-readable elements
	source_tmp,  not_readable_or_not_regular = collect_files( @source )
	@source = source_tmp.flatten.compact.dup
	@logger.debug("SOURCE: len = #{@source.length}, #{@source.inspect}")
	# check type (image/audio)
	no_decode_delegate = Array.new
	source_tmp = Array.new
		
	threads = CinemaslidesCommon::process_elements_multithreaded( @source ) {|i, indices|
	    start_index, end_index = indices[i]
	    @logger.debug("T:#{i}, START CHECKFILES THREAD start = #{start_index}, end = #{end_index}")
	    Thread.current["source_tmp"], 
	    Thread.current["source_audio"], 
	    Thread.current["no_decode_delegate"] = check_files(@source[ start_index .. end_index ])
	}
	threads.each {|t| 
	  source_tmp << t["source_tmp"]
	  source_audio << t["source_audio"]
	  no_decode_delegate << t["no_decode_delegate"]
	}                            
	source_tmp.flatten!.compact!
	source_audio.flatten!.compact!
	no_decode_delegate.flatten!.compact!	

	drops = FALSE
	if not_readable_or_not_regular.size > 0
	  drops = TRUE
	  @logger.debug( "Not readable or no regular file: #{ not_readable_or_not_regular.join( ', ' ) }" )
	elsif not_readable_or_not_regular.size == 0 and source_tmp.size > 0
	  @logger.debug( "All files readable and regular files" )
	end
	
	if no_decode_delegate.size > 0
	  drops = TRUE
	  @logger.debug( "No decode delegates for #{ no_decode_delegate.join( ', ' ) }" )
	end
	
	if source_tmp.length == 0 and !@audio_only
	  @logger.info( drops  ? "No useable image files" : "No image files specified")
	  return @source, source_audio, no_decode_delegate, FALSE
	end
	
	if drops
	  if @dont_drop
	    return @source, source_audio, no_decode_delegate, FALSE
	  else
	    @logger.debug( "Dropped some unuseable files. Say '--dont-drop' to exit in that case." )
	  end
	end
	@source = source_tmp.dup
      end
      
      if !@audio_only and !@image_sequence_class.n_of_images_ok?(@source)
	return @source, source_audio, no_decode_delegate, FALSE
      end
      
      @logger.debug( "Images: #{ @source.join( ', ' ) }" )
      @logger.debug( "Audio files: #{ source_audio.join( ', ' ) }" ) unless source_audio.empty?
      if no_decode_delegate.nil?
	@logger.debug( "No decode delegates for: Not checked" )
      else
	@logger.debug( "No decode delegates for: #{ no_decode_delegate.join( ', ' ) }" ) unless no_decode_delegate.empty?
      end
      
      return @source, source_audio, no_decode_delegate, TRUE
      #      images,  audio,        not decodeable,     files_ok?
    end # seperate_and_check_files
    
    private 
    
    # collect all file of the array source
    # and go into directories recursively
    # returns two arrays: an array of all the file names and an array of all the
    # not readable or not regular file names
    def collect_files( source )
      not_readable_or_not_regular = Array.new
      source_tmp = Array.new
      source.each do |element|
	if File.exists?( element ) 
	  if CSTools.is_directory_dereference_links?( element )
	    s2, nr2 = collect_files( Dir.glob( "#{ element }/*" ).sort )
	    not_readable_or_not_regular << nr2
	    source_tmp << s2
	  elsif CSTools.is_file_dereference_links?( element )
	    source_tmp << element
	  else
	    not_readable_or_not_regular << element
	    @logger.debug( "No regular file: #{ element }" )
	  end
	else
	  not_readable_or_not_regular << element
	  @logger.debug( "Not readable: #{ element }" )
	end
      end
      return source_tmp.flatten.compact.dup, not_readable_or_not_regular.flatten.compact.dup
    end
    
    def check_files(source)
      source_audio = Array.new
      no_decode_delegate = Array.new
      source_tmp = source.clone
	source.each do |file|
	  @logger.debug("check file >>#{ file }<<")
	  image_identify = ShellCommands.image_identify_command(file).chomp
	  if image_identify.empty?
	    audio_identify = ShellCommands.soxi_V0_t_command(file).chomp
	    if audio_identify.empty?
	      no_decode_delegate << file
	      source_tmp.delete( file )
	      @logger.debug( "#{ file }: No decode delegate" )
	    else
	      source_audio << file
	      source_tmp.delete( file )
	      audiofile_duration = '(' + ShellCommands.soxi_V0_d_command(file).chomp + ')'
	      @logger.debug( "#{ audio_identify.upcase } #{ audiofile_duration }: #{ file }" )
	    end
	  # see http://www.imagemagick.org/discourse-server/viewtopic.php?f=1&t=16398
	  # basically IM defers deep analysis of xml to the coder.
	  # the lightweight identify ping of xml might return false positives
	  elsif image_identify == "SVG"
	    xml = Nokogiri::XML( File.open( file ) )
	    if xml.search( 'svg', 'SVG' ).empty?
	      no_decode_delegate << file
	      source_tmp.delete( file )
	      @logger.debug( "No <svg> node: #{ file }" )
	    else # svg maybe useable
	      @logger.debug( "#{ image_identify }: #{ file }" )
	    end
	  else # file is useable
	    dimensions = ShellCommands.IM_convert_info_command(file).chomp
	    @logger.debug( "#{ image_identify } #{ dimensions }: #{ file }" )
	  end
	end # @source.each do |file|
	return source_tmp, source_audio, no_decode_delegate
    end
    

  end #class
  
end