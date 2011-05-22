module InputType

  require 'Logger'
  require 'ShellCommands'
  require 'AudioSequence'
  ShellCommands = ShellCommands::ShellCommands
  
  AUDIOSUFFIX_REGEXP = Regexp.new(/(mp3|MP3|wav|WAV|flac|FLAC|aiff|AIFF|aif|AIF|ogg|OGG)$/)
  
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
    # and to convert the video into an imagesequence.
    # Fading has to be set to cut and duration to 0.041666667.
    def seperate_and_check_files
      # seperate and check files
      # return [ [images], [audiofiles], [no_code_delagate_files] ]
      raise NotImplementedError, "Do not instanciate this abstract class: InputType"
    end
  end
  
  # TODO this is just do show, that it is possible, nothing final
  # fps fixed to 24, should be obtained from avcoontainer
  # Maybe better name for image_output_dir and audio_from_av should be chosen.
  # The concept of assets should also be chosen here, that means an image sequence 
  # should be created only once
  class AVContainerInputType < InputType
    def initialize (avfile, dont_check, dont_drop, transition_and_timing)
      @logger = Logger::Logger.instance
      @avfile = avfile
      @cinemaslidesdir = File.get_cinemaslidesdir
      @options = OptParser::Optparser.get_options     
      @options.fade_in_time = 0
      @options.duration = 1.0/24.0
      @options.fade_out_time = 0
    end
    def seperate_and_check_files
      if @avfile.empty?
	@logger.info( 'No files specified' )
	return Array.new, Array.new, Array.new, FALSE
      end
      @image_output_dir = File.join(@cinemaslidesdir, "tif_from_av_#{ get_timestamp }")
#      @image_output_dir = "/BACKUPS/DCP-TEST/tif_from_av_2011-05-18T11:27:11+02:00"
      
      Dir.mkdir( @image_output_dir )
      @audio_from_av = File.join(@cinemaslidesdir, "audio_from_av_#{ get_timestamp }_" +AudioSequence::FILE_SUFFIX_PCM)
#      @audio_from_av = "/BACKUPS/DCP-TEST/audio_from_av_2011-05-18T11:27:13+02:00_.wav"
      # TODO create a method in ShellCommands for this
      `ffmpeg -y -i "#{ @avfile }" -an -r 24  -threads 8 -b 10000k #{File.join(@image_output_dir, "%06d.tiff")}`
      `ffmpeg -y -i "#{ @avfile }" -acodec pcm_s24le -r 24 -ar 48000 #{ @audio_from_av }`
      
#      return Dir.glob( "/BACKUPS/DCP-TEST/tif_from_av_2011-05-18T11:27:11+02:00/*" ).sort,  ["/BACKUPS/DCP-TEST/audio_from_av_2011-05-18T11:27:13+02:00_.wav"], nil, TRUE
      
      return Dir.glob( "#{ @image_output_dir }/*" ).sort,  [@audio_from_av], nil, TRUE
      
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
# FIXME filenames with spaces won't work. bummer
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
	  if element =~ AUDIOSUFFIX_REGEXP
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
  
end