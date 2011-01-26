module InputType

  require 'Logger'
  require 'ShellCommands'
  ShellCommands = ShellCommands::ShellCommands
  
  class InputType
    def initialize (source)
      @logger = Logger::Logger.instance
      @source = source
    end
    # seperates files into three categories
    # imagesequence, audio and files with no code delegate
    # and returns an array with arrays of these files
    # so if you want to use this class to seperate a videofile
    # with sound, this seperate function has to seperate the sound from the video
    # and to convert the video into an imagesequence
    def seperate_and_check_files
      # seperate and check files
      # return [ [images], [audiofiles], [no_code_delagate_files] ]
      raise NotImplementedError, "Do not instanciate this abstract class: InputType"
    end
  end
  
  class SlideshowInputType < InputType
    
    def initialize( source, dont_check, dont_drop, transition_and_timing )
      super( source )
      @dont_check = dont_check
      @dont_drop = dont_drop
      @transition_and_timing = transition_and_timing
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
	source_tmp = @source.clone
	@source.each do |element|
	  if element =~ /(mp3|MP3|wav|WAV|flac|FLAC|aiff|AIFF|aif|AIF|ogg|OGG)$/
	    source_audio << element
	    source_tmp.delete( element )
	  end
	end
	@source = source_tmp.clone
      else # check files
	# remove un-readable elements
	not_readable = Array.new
	source_tmp = Array.new
	@source.each do |element|
	  if File.exists?( element )
	    if File.is_directory?( element )
	      more = Dir.glob( "#{ element }/*" ).sort # this breaks fast (subdirs)
	      source_tmp << more
	    else
	      source_tmp << element
	    end
	  else
	    not_readable << element
	    @logger.debug( "Not readable: #{ element }" )
	  end
	end
	@source = source_tmp.flatten.compact.dup
	
	# check type (image/audio)
	no_decode_delegate = Array.new
	drops = FALSE
	source_tmp = @source.clone
	@source.each do |file|
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
	end
	if not_readable.size > 0
	  drops = TRUE
	  @logger.debug( "Not readable: #{ not_readable.join( ', ' ) }" )
	elsif not_readable.size == 0 and source_tmp.size > 0
	  @logger.debug( "All files readable" )
	end
	if no_decode_delegate.size > 0
	  drops = TRUE
	  @logger.debug( "No decode delegates for #{ no_decode_delegate.join( ', ' ) }" )
	end
	if source_tmp.length == 0
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
      
      if !ImageSequence.const_get(image_sequence_classnames[@transition_and_timing.first]).n_of_images_ok?(@source)
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
    end # seperate_and_check_files

  end #class
  
  # TODO
  class AVContainerInputType < InputType
  end

end