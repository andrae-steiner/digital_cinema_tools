module OutputType
  
# Here the real work is done
# see create_output_type
#     create_output_type2

  require 'Encoder'
  require 'OptParser'
  require 'ShellCommands'
  require 'Asset'
  require 'ImageSequence'
  require 'AudioSequence'
  require 'MXF'
  require 'DCP'
        
  TESTING = FALSE

  
  ShellCommands = ShellCommands::ShellCommands
  SRGB_TO_XYZ = "0.4124564 0.3575761 0.1804375 0.2126729 0.7151522 0.0721750 0.0193339 0.1191920 0.9503041"
  ITUREC709_TO_XYZ = "0.412390799265959  0.357584339383878  0.180480788401834 0.21263900587151 0.715168678767756 0.0721923153607337 0.0193308187155918 0.119194779794626 0.950532152249661"


  THUMB_DIMENSIONS_FACTOR = 6

  class Summary_context
    attr_reader :source, :n_sequence_frames, :signer_cert_obj
    def initialize(source, n_sequence_frames, signer_cert_obj)
      @source = source
      @n_sequence_frames = n_sequence_frames
      @signer_cert_obj = signer_cert_obj
    end
  end

  class Final_report_context
    attr_reader :n_sequence_frames, :fps, :transition_and_timing, :keep, :framecount, :source, :workdir
    def initialize( n_sequence_frames, fps, transition_and_timing, keep, framecount, source, workdir )
      @n_sequence_frames = n_sequence_frames
      @fps = fps
      @transition_and_timing = transition_and_timing
      @keep = keep
      @framecount = framecount 
      @source = source
      @workdir = workdir
    end
  end
  
  class Final_kdm_report_context
    attr_reader :workdir
    def initialize( workdir )
      @workdir = workdir
    end
  end
  
  class OutputType
    attr_reader :cinemaslidesdir
    def initialize(mandatory, dcp_functions)
      @options = OptParser::Optparser.get_options            
      @logger = Logger::Logger.instance
      @mandatory = mandatory
      @dcp_functions = dcp_functions
      @cinemaslidesdir = File.get_cinemaslidesdir
    end  
    
    def all_mandatory_tools_available?
      available_mandatory, missing_mandatory = check_external( @mandatory )
      @logger.debug( "Available tools: #{ available_mandatory.sort.join(', ') }" ) unless available_mandatory.empty?
      if !missing_mandatory.empty?
        @logger.info( "Required tools: #{ @mandatory.join( ', ' ) }" )
        @logger.info( "Missing tool#{ missing_mandatory.size != 1 ? 's' : '' }: #{ missing_mandatory.join( ', ' ) }" )
	@logger.info( "Check your installation" )
      end
      return missing_mandatory.empty?
    end
    
    private
    
    def display_summary (summary_context)
      raise NotImplementedError, "Do not instanciate this abstract class: OutputType"
    end
    
    def final_report (context)
      raise NotImplementedError, "Do not instanciate this abstract class: OutputType"
    end
    
    def cleanup_workdir(keep, workdirs)
      return if keep
      @logger.info( "Removing temporary files (Say '--keep' to keep them)" )
      workdirs.each do |dir|
	if File.dirname( @options.dcpdir ) != dir
	  ShellCommands.rm_rf_command( dir )
	end
      end
    end
          
    def check_external( requirements )
      available_tools = Array.new
      missing_tools = Array.new
      requirements.each do |tool|
	exitstatus = system "which #{ tool } > /dev/null 2>&1"
	if exitstatus
	  @logger.debug( "Available: #{ tool }" )
	  available_tools << tool
	else
	  @logger.debug( "Missing: #{ tool }" )
	  missing_tools << tool
	end
      end
      return available_tools, missing_tools
    end
    
  end
  
  class KDMOutputType < OutputType
    def initialize(mandatory, dcp_functions)
      super(mandatory, dcp_functions)
    end
    def final_report (context)
      @logger.info( "Pick up KDM at #{ context.workdir }" )
      @logger.info( 'KDM done' )
    end
  end # KDMOutputType
  
  class AudioVideoOutputType < OutputType
    attr_reader :dimensions, :workdir, :conformdir, :dcp_image_sequence_name, :thumbsdir, :assetsdir, :assetsdir_audio, :keysdir, :compress_parameter, :depth_parameter, :thumbs_dimensions, :jpeg2000_codec, :size, :dcp_wrap_stereoscopic
    def initialize(mandatory, dcp_functions)
      super(mandatory, dcp_functions)
      @dimensions = width_x_height
      @thumbs_dimensions = calc_thumbsdimensions(THUMB_DIMENSIONS_FACTOR)
      @jpeg2000_codec = @options.jpeg2000_codec
      @size = @options.size
      @dcp_wrap_stereoscopic = @options.dcp_wrap_stereoscopic
    end

    # TODO we should probably feed already "create_output_type" with a list of SMPTE::DCPAsset elements.
    #
    # But in this case MXF generation has to be delayed until DCP::DCP.add_cpl
    def create_output_type( source, source_audio, signature_context)
      create_output_type2( source, source_audio, signature_context)
      final_report(Final_report_context.new(
	@image_sequence.n_sequence_frames, @options.fps, @options.transition_and_timing, @options.keep, @image_sequence.framecount,  source, @workdir ))
      cleanup_workdir( @options.keep )
      done_message
    end
    
    
    private 
    
    def done_message
      raise NotImplementedError, "Do not instanciate this abstract class: AudioVideoOutputType"
    end
    
    def create_output_type2 (source, source_audio, signature_context)
      setup_output_directories(source.empty?, source_audio.empty?)
      @image_sequence = ImageSequence.const_get(image_sequence_classnames[@options.transition_and_timing.first]).new(
	source          = source, 
	output_type_obj = self,
	output_format   = @options.output_format, 
	resize          = @options.resize,
	fps             = @options.fps,
	black_leader    = @options.black_leader,
	black_tail      = @options.black_tail,
	fade_in_time    = @options.fade_in_time,
	duration        = @options.duration,
	fade_out_time   = @options.fade_out_time, 
	crossfade_time  = @options.crossfade_time) 
      @audio_sequence = AudioSequence::AudioSequence.new(
	source           = source_audio,
	image_sequence   = @image_sequence,
	output_type_obj  = self, 
	fps              = @options.fps,
	audio_samplerate = @options.audio_samplerate,
	audio_bps        = @options.audio_bps, 
	black_leader     = @options.black_leader, 
	black_tail       = @options.black_tail
	)
      display_summary(
	Summary_context.new(
	      source = source,
	      n_sequence_frames = @image_sequence.n_sequence_frames,
	      signer_cert_obj = signature_context.signer_cert_obj
	))  
      ### Process all images
      if @options.montage
	thumbs_asset = @image_sequence.create_montage_preview
	if ENV[ "DISPLAY" ].nil?
	  @logger.warn( "DISPLAY not set. Skipping montage summary. #{ @options.keep ? nil : 'Say --keep to keep preview files.' }" )
	else
	  @logger.warn( "Montage summary #{ @options.output_type }. Exit with ESC or 'q'" )
	  ShellCommands.display_command( thumbs_asset )
	end
	exit if !agree( "Continue? " )
      end # montage

      ### Create all frames
      @final_audio = @audio_sequence.audio_source_to_pcm if !source_audio.empty?

      Dir.mkdir( @workdir ) unless File.exists?( @workdir )
      Dir.mkdir( @conformdir )
           
      @image_sequence.create_leader
      @image_sequence.create_transitions
      @image_sequence.create_trailer
      ###
     
    end # create_output_type2

    def cleanup_workdir(keep, workdirs)
      super(keep, workdirs)
    end
    
    def setup_output_directories(source_empty, source_audio_empty)
      @workdir = File.join( @cinemaslidesdir, "#{ File.basename( $0 ) }_#{ get_timestamp }_#{ @options.output_type }" )
      @conformdir = File.join( @workdir, "conform" )
      @dcp_image_sequence_name = File.join( @workdir, @dcp_functions.dcp_image_sequence_basename )
      @thumbsdir = File.join( @cinemaslidesdir, "thumbs" )
      @assetsdir = File.join( @cinemaslidesdir, "assets" )
      @assetsdir_audio = File.join( @cinemaslidesdir, 'assets-audio' )
      @keysdir = File.join( @cinemaslidesdir, 'keys' )

      OptParser::Optparser.set_dcpdir_option(File.join( @workdir, 'dcp' ))

      if confirm_or_create( @cinemaslidesdir )
	@logger.debug( "#{ @cinemaslidesdir } is writeable" )
      else
	@logger.critical( "#{ @cinemaslidesdir } is not writeable. Check your mounts or export CINEMASLIDESDIR to point to a writeable location." )
	exit
      end
      unless source_empty # TODO audio-only DCP
	Dir.mkdir( @assetsdir ) unless File.exists?( @assetsdir )
      end
      unless source_audio_empty
	Dir.mkdir( @assetsdir_audio ) unless File.exists?( @assetsdir_audio )
      end
    end
    
    def final_report (context)
      sequence_duration = context.n_sequence_frames / context.fps
      frames = context.framecount - 1
      @logger.debug( "#{ context.n_sequence_frames } frames intended by numbers (#{ hours_minutes_seconds_verbose( sequence_duration ) })" )
      @logger.debug( "#{ frames } frames written" )
      @logger.info( "Cinema Slideshow is #{ hours_minutes_seconds_verbose( ( frames ) / context.fps ) } long (#{ context.source.length } image#{ 's' * ( context.source.length == 1 ? 0 : 1 )} | #{ context.transition_and_timing.join(',').gsub(' ', '') } | #{ frames } frames | #{ context.fps } fps)" )
    end
    
    def confirm_or_create( location )
    # location (a directory) might exist and be either writeable or not.
    # it might not exist and be either writeable (read 'can be created') or not.
    # since we want to be able to specify a "deep" path (topdir/with/children/...) File.writable?() wouldn't work.
      testfile = File.join( location, ShellCommands.uuid_gen )
      if File.exists?( location )
	begin
	  result = ShellCommands.touch_command( testfile )
	  File.delete( testfile )
	  return TRUE # location exists and we can write to it
	rescue Exception => result
	  return FALSE # location exists but we can't write to it
	end
      else
	begin
	  result = FileUtils.mkdir_p( location )
	  return TRUE # location created, hence writeable
	rescue Exception => result
	  return FALSE
	end
      end
    end

    # fit custom aspect ratios into the target container dimensions (1k for preview, 2k/4k for fullpreview/dcp)
    def scale_to_fit_container( width, height, container_width, container_height )
      factor = container_height / container_width > height / width ? container_width / width : container_height / height
      @logger.debug( "Scaling factor to fit custom aspect ratio #{ width } x #{ height } in #{ @options.size } container: #{ factor }" )
      width_scaled = width * factor
      height_scaled = height * factor
      return width_scaled.floor, height_scaled.floor
    end
    
    # target container dimensions are upscaled from 1k numbers
    # (1k for preview, 2k and 4k for fullpreview and dcp)
    # any custom aspect ratio is scaled to fit the target container
    def width_x_height
      container_multiplier = @options.size.split( '' ).first.to_i
      container_width = 1024.0 * container_multiplier
      container_height = 540.0 * container_multiplier
      @logger.debug( "Container: #{ container_width } x #{ container_height } (1k multiplier: #{ container_multiplier })" )
      case @options.aspect
      when OptParser::ASPECT_CHOICE_FLAT # 1.85 : 1
	width, height = 999, 540 # 1.85
      when OptParser::ASPECT_CHOICE_SCOPE # 2.39 : 1
	width, height = 1024, 429 # 2.38694638694639
      when OptParser::ASPECT_CHOICE_HD # 1.77 : 1
	width, height = 960, 540 # 1.77777777777778
      else # Custom aspect ratio
	custom_width, custom_height = @options.aspect.split( 'Custom aspect ratio:' ).last.split( 'x' )
	width, height = scale_to_fit_container( custom_width.to_f, custom_height.to_f, container_width, container_height )
	return [ width, height ].join( 'x' )
      end
      width *= container_multiplier
      height *= container_multiplier
      return [ width, height ].join( 'x' )
    end
    
    def calc_thumbsdimensions(factor)
      x,y = @dimensions.split( 'x' ) # ugh
      x = x.to_i / factor # ugh ugh
      y = y.to_i / factor # ...
      return [ x,y ].join( 'x' ) # oh dear
    end
    
  end # AudioVideoOutputType
  
  class PreviewOutputType < AudioVideoOutputType
    attr_reader :compress_parameter, :depth_parameter
    def initialize(mandatory, dcp_functions)
      super(mandatory, dcp_functions)
      @compress_parameter = "  "
      @depth_parameter    = "-depth 8 "
    end
    
    def convert_resize_extent_color_specs( image, filename )
      ShellCommands.p_IM_convert_resize_extent_color_specs( image, filename, @options.resize, @dimensions)
    end

    def convert_apply_level( image, level, filename )
      ShellCommands.p_IM_convert_apply_level( image, level, filename )
    end  

    def create_blackframe (file)
      ShellCommands.p_IM_black_frame( file, @dimensions )
    end
    
    
    def asset_suffix(suffix)
      '_pre_.' + suffix
    end
    
    private
    
    def create_output_type2( source, source_audio, signature_context)
      super(source, source_audio, signature_context)
      sequence = File.join( "#{ @conformdir }", "*.#{ @options.output_format }" )
      audio = ( source_audio.empty? ? '' : '-audiofile ' + @final_audio )
      if ENV[ "DISPLAY" ].nil?
	@logger.warn( "DISPLAY not set. Skipping preview" )
      else
	@logger.warn( "Loop #{ @options.output_type }. Exit with ESC or 'q'" )
	mplayer_vo = ""
	ShellCommands.mplayer_preview_command(  sequence, audio, @options.fps, @options.output_format, mplayer_vo, @options.mplayer_gamma)
      end
    end
    
    def cleanup_workdir(keep)
      super(keep, [ @workdir ] )
    end
    
    def final_report (context)
      super(context)
    end

    def done_message
        @logger.info( "Preview done" )
    end
    
    def display_summary (summary_context)
      @logger.info( "Creating #{ @options.output_type } (#{ @options.aspect } #{ @dimensions } @ #{ @options.fps } fps)" )
      @logger.info( "Number of images: #{ summary_context.source.size }" )
      @logger.info( "Transition specs: #{ @options.transition_and_timing.join( ',' ) }" )
      @logger.info( "Projected length: #{ hours_minutes_seconds_verbose( summary_context.n_sequence_frames / @options.fps ) }" )
    end
                
  end # PreviewOutputType
  
  class DCPOutputType < AudioVideoOutputType
    attr_reader :compress_parameter, :depth_parameter
    def initialize(mandatory, dcp_functions)
      super(mandatory, dcp_functions)
      @compress_parameter = "-compress none "
      @depth_parameter    = "-depth 12 "
    end
        
    def convert_resize_extent_color_specs( image, filename )
      ShellCommands.smpte_dcp_IM_convert_resize_extent_color_specs( image, filename, @options.resize, @dimensions)
    end
    
    def convert_apply_level( image, level, filename )
      ShellCommands.smpte_dcp_IM_convert_apply_level( image, level, filename)
    end  
    
    def create_blackframe (file)
       ShellCommands.smpte_dcp_IM_black_frame( file, @dimensions )
    end
    
    def all_mandatory_tools_available?
      available_codecs, missing_codecs = check_external( encoder_prog.values )
      if available_codecs.empty?
	@logger.warn( "No JPEG 2000 codec available (Needed for DCP creation). Check your installation" )
	return FALSE
      end
      enc = encoder_prog[@options.jpeg2000_codec]
      if missing_codecs.include?( enc )
	@logger.info( "#{ enc } not available. Check your installation" )
	return FALSE
      end
      if @options.sign
	mandatory << 'xmlsec1'
      end
      if @options.dcp_encrypt
	mandatory << 'kmrandgen'
	mandatory << 'xmlsec1'
      end
      available_mandatory, missing_mandatory = check_external( @mandatory )
      available_mandatory += available_codecs unless available_codecs.nil?

      @logger.debug( "Available tools: #{ available_mandatory.sort.join(', ') }" ) unless available_mandatory.empty?
      @logger.debug( "Missing tools: #{ ( missing_mandatory + missing_codecs ).join(', ') }" ) unless ( missing_mandatory.empty? or missing_codecs.empty? )
      @logger.debug( "All necessary tools available" ) if ( missing_mandatory.empty? and missing_codecs.empty? ) # FIXME

      if missing_mandatory.size > 0
	@logger.info( "Check your installation" )
	return FALSE
      end
      return TRUE
    end
        
    def asset_suffix(suffix)
      fps_suffix = @options.dcp_wrap_stereoscopic ? '48' : @options.fps.floor.to_s 
      dcp_output_type_suffix = suffix == 'j2c' ? '_' + encoder_ids[@options.jpeg2000_codec] + '_' + fps_suffix : ''
      dcp_output_type_suffix + "_." + suffix
      
      
#        assetname = File.join( @assetsdir, id + "_#{ @dimensions }_#{ @resize == TRUE ? 'r' : 'nr' }#{ level.nil? ? '' : '_' + level.to_s }#{ @output_type == 'dcp' ? suffix == 'j2c' ? '_' + @encoder_id + '_' + ( @dcp_wrap_stereoscopic == TRUE ? '48' : fps.floor.to_s ) : '' : '_pre' }_.#{ suffix }" )

      
      
    end

    
    private 
    

    def create_output_type2( source, source_audio, signature_context)
      super( source, source_audio, signature_context)
      
      # jpeg2000_conversion( @image_sequence )
      @dcp_functions.convert_to_dcp_image_format_threaded( @image_sequence, self )
      
      image_mxf_track = MXF::VideoMXFTrack.new(
	dcpdir = @options.dcpdir, 
	keysdir = @keysdir,
	steroscopic = @options.dcp_wrap_stereoscopic, 
	dcp_encrypt = @options.dcp_encrypt, 
	fps = @options.fps)
      t1 = Thread.new do
	@logger.info( 'Write image trackfile ...' )  
	image_mxf_track.write_asdcp_track( file =  @dcp_image_sequence_name)
	@logger.debug( "Image trackfile UUID: #{ image_mxf_track.mxf_uuid }" )
      end
      
      unless source_audio.empty?
	audio_mxf_track = MXF::AudioMXFTrack.new(
	  dcpdir = @options.dcpdir, 
	  keysdir = @keysdir,
	  dcp_encrypt = @options.dcp_encrypt, 
	  fps = @options.fps)
        t2 = Thread.new do
	  @logger.info( 'Write audio trackfile ...' )
	  # FIXME 2.0 sound only here (v0.2010.11.19), hence no label. might be trouble on some servers
	  audio_mxf_track.write_asdcp_track( file =  @final_audio)
	  @logger.debug( "Audio trackfile UUID: #{ audio_mxf_track.mxf_uuid }" )
	end
      end
      
      t1.join()
      t2.join() if (!source_audio.empty?)
      
      smpte_dcp = DCP::DCP.new(
	  dcpdir            = @options.dcpdir,
	  issuer            = @options.issuer,
	  creator           = "#{ AppName } #{ AppVersion } smpte",
	  annotation        = @options.annotation,
	  sign              = @options.sign,
	  signature_context = signature_context,
	  dcp_functions     = @dcp_functions)
 
#for testing
      subtitle_filename =  "/home/home-10.1/Documents/Programmkino/DCP-TEST/Untertitel/Maener_al_Dente_dtUt_R4.xml" 
      font_filename = "/home/home-10.1/Documents/Programmkino/DCP-TEST/Untertitel/arial.ttf"
#for testing
      
      dcp_audio_asset = source_audio.empty? ? nil : DCP::DCPMXFAudioAsset.new( audio_mxf_track.mxf_file_name )
      dcp_image_asset = DCP::DCPMXFImageAsset.new( image_mxf_track.mxf_file_name )
            
# for testing      
      line1 = DCP::DCSubtitleLine.new("bottom", "center", 0, 7, "Ja, unser mündlicher Vertrag war anders,")
      line2 = DCP::DCSubtitleLine.new("bottom", "center", 0, 14, "Ja, unser mündlicher Vertrag war anders,")
      st1 = DCP::DCSingleSubtitle.new( "00:00:00:011", "00:00:03:042", 0, 0, [line1])
      st2 = DCP::DCSingleSubtitle.new( "00:00:07:011", "00:00:10:042", 0, 0, [line1, line2])
      
      st_uuid = ShellCommands.uuid_gen
      dc_subtitle = DCP::DC_SUBTITLE.new( 
	subtitle_id       =  st_uuid, 
	movie_title       = "testmovie", 
	reel_number       = 1, 
	language          = "German", 
	font_id           = "Font1", 
	font_uri          = File.basename(font_filename), 
	font_size         = 47, 
	font_weight       = "normal", 
	font_color        = "FFFFFFFF", 
	font_effect       = "shadow", 
	font_effect_color = "FF000000", 
	subtitle_list     = [st1, st2] )
      st_filename = DCP::DCP::st_file( @options.dcpdir, st_uuid )
      File.open( st_filename, 'w' ) { |f| f.write( dc_subtitle.xml ) } if TESTING
       
      dcp_subtitle_asset = DCP::DCPSubtitleAsset.new( st_filename, edit_rate = "24 1", intrinsic_duration=168, entry_point=0, duration=168) if TESTING
#for testing
      
      smpte_dcp.add_cpl(
	[ DCP::DCPReel.new(
           dcp_image_asset, 
           dcp_audio_asset,
           subtitle_asset = !TESTING ? nil : dcp_subtitle_asset # for testing
        ) ],
	content_title = @options.dcp_title,
	content_kind = @options.dcp_kind,
	rating_list = nil
      )
      
      smpte_dcp.add_font(font_filename, DCP::MIMETYPE_TTF)  if TESTING
      
      smpte_dcp.write_ov_dcp
           
      # readme and report
      readme_file_name = @options.annotation.gsub( /[\\\/\&: ]/, '_' ) + '.readme'
      readme_file_path = File.join( @options.dcpdir, readme_file_name )
      File.open( readme_file_path, 'w' ) { |f| f.write( CINEMASLIDES_COMMANDLINE + "\n" ) }
    end
    
    def display_summary (summary_context)
      @logger.info( "Creating#{ @options.sign ? ' signed' : '' }#{ @options.dcp_encrypt ? ' and encrypted' : '' }#{ @options.dcp_wrap_stereoscopic ? ' 3D' : ' 2D' } #{ @options.size.upcase } DCP (#{ @options.aspect } #{ @dimensions } @ #{ @options.fps } fps). Encoder: #{ @options.jpeg2000_codec }" )
      @logger.info( "Number of images: #{ summary_context.source.size }" )
      @logger.info( "Transition specs: #{ @options.transition_and_timing.join( ',' ) }" )
      @logger.info( "Projected length: #{ hours_minutes_seconds_verbose( summary_context.n_sequence_frames / @options.fps ) }" )
      @logger.info( "Title:            #{ @options.dcp_title }" )
      @logger.info( "Annotation:       #{ @options.annotation }" )
      @logger.info( "Issuer:           #{ @options.issuer }" )
      @logger.info( "Kind:             #{ @options.dcp_kind }" )
      if @options.sign
	@logger.info( "Signer:           #{ summary_context.signer_cert_obj.subject.to_s }" )
      end  
    end
    
    def final_report (context)
      super(context)
      @logger.info( "Pick up preview files at #{ context.workdir }/" ) if context.keep 
      @logger.info( "Pick up temporary files at #{ context.workdir }/" ) if context.keep 
      @logger.info( "Pick up DCP at #{ @options.dcpdir }" ) 
    end
    
    def cleanup_workdir(keep)
      super(keep, [ @conformdir, @dcp_image_sequence_name, @workdir ]  )
    end
    
    def done_message
        @logger.info( "DCP done" )
    end

#    def jpeg2000_conversion( image_sequence )
#      
#      # Global:
#      #		@logger
#      #		@dcp_image_sequence_name
#      #		@options.jpeg2000_codec
#      #		@options.size
#      #		@options.dcp_wrap_stereoscopic
#      #		
#      
#      Dir.mkdir( @dcp_image_sequence_name )
#      ## JPEG 2000 encoding
#      @logger.info( "Encode to JPEG 2000" )
#      filemask = File.join( image_sequence.conformdir, "*.#{ image_sequence.output_format }" )
#      files = Dir.glob( filemask ).sort
#
#      counter = 0
#      previous_asset = ""
#      
#      encoder = Encoder.const_get(encoder_classnames[@options.jpeg2000_codec]).new(
#	size = @options.size,
#	stereo = @options.dcp_wrap_stereoscopic,
#	fps = image_sequence.fps)
#      
#      files.each do |file|
#	counter += 1
#	asset_link = File.join( @dcp_image_sequence_name, File.basename( file ).gsub( '.tiff', '' ) + '.j2c' )
#	if File.dirname( File.readlink( file ) ) == image_sequence.conformdir # 1st file is always a link to the asset depot
#	  @logger.debug( "link previous_asset = #{ previous_asset }, asset_link = #{ asset_link }" )
#	  File.link( File.expand_path(previous_asset), asset_link ) 
#	  @logger.cr( "Skip (Full level): #{ File.basename( file ) } (#{ counter } of #{ files.size })" )
#	else
#	  asset, todo = image_sequence.asset_functions.check_for_asset( file, 'j2c', level = nil ) # possible "Skip" message only with debug verbosity
#	  previous_asset = asset
#	  @logger.debug( "TODO = #{ todo }, @options.output_format = #{ @options.output_format } ")
#	  if todo
#	    @logger.cr( "#{ @options.jpeg2000_codec }: #{ File.basename( file ) } (#{ counter } of #{ files.size })" )
#	    @logger.debug("@options.jpeg2000_codec = #{ @options.jpeg2000_codec }")
#	    @logger.debug("Encode  >>#{file}<< to >>#{asset}<<. ");
#	    encoder.encode( file, asset )
#	  end
#	  File.link( File.expand_path(asset),  asset_link )
#	end
#      end
#    end # jpeg2000_conversion

    def setup_output_directories(source_empty, source_audio_empty)
      super(source_empty, source_audio_empty)
      # silently ignore option.dcp_user_output_path when previewing
      # ask for confirmation to add files if -o | --dcp_out is set and the location already exists and is not empty
      if @options.dcp_user_output_path != nil and File.exists?( @options.dcpdir ) and Dir.entries( @options.dcpdir ).size > 2 # platform-agnostic Dir.empty? anyone?
	if File.writable?( @options.dcpdir )
	  if ENV[ 'HOME' ] == File.join( File.dirname( @options.dcpdir ), File.basename( @options.dcpdir ) ) # confirm direct write into HOME
	    @logger.critical( "Cluttering HOME" )
	    exit if !agree( "Are you sure you want to write DCP files directly into #{ ENV[ 'HOME' ] }? " )
	  else
	    exit if !agree( "#{ @options.dcpdir } already exists. Add current DCP files to it? " )
	  end
	end
      end
      if confirm_or_create( @options.dcpdir )
	@logger.debug( "#{ @options.dcpdir } is writeable" )
      else
	@logger.critical( "#{ @options.dcpdir } is not writeable. Check your mounts and permissions." )
	exit
      end
      
      # location of content keys
      if @options.dcp_encrypt
	Dir.mkdir( @keysdir ) unless File.exists?( @keysdir )
      end

    end

    
  end # DCPOutputType
  
  
end

