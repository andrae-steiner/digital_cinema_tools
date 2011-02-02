module OptParser

  require 'ShellCommands'
  OUTPUT_TYPE_CHOICE_PREVIEW = 'preview'
  OUTPUT_TYPE_CHOICE_FULLPREVIEW = 'fullpreview'
  OUTPUT_TYPE_CHOICE_DCP = 'dcp' 
  OUTPUT_TYPE_CHOICE_KDM = 'kdm' 
  ENCODER_CHOICE_OJ_TM = 'openjpeg-tm'
  ENCODER_CHOICE_OJ = 'openjpeg'
  ENCODER_CHOICE_KAKADU = 'kakadu'
  TRANSITION_CHOICE_CUT = 'cut'
  TRANSITION_CHOICE_FADE = 'fade'
  TRANSITION_CHOICE_CROSSFADE = 'crossfade'
  INPUT_TYPE_CHOICE_SLIDE = 'slideshow'
  INPUT_TYPE_CHOICE_AV = 'avcontainer'
  CONTAINER_SIZE_2K = '2k'
  CONTAINER_SIZE_4K = '4k'
  ASPECT_CHOICE_FLAT = 'flat'
  ASPECT_CHOICE_SCOPE = 'scope'
  ASPECT_CHOICE_HD = 'hd'
  SAMPLE_RATE_CHOICE_48000 = '48000'
  SAMPLE_RATE_CHOICE_48K   = '48k'
  SAMPLE_RATE_CHOICE_96000 = '96000'
  SAMPLE_RATE_CHOICE_96K   = '96k'
  VERBOSITY_CHOICE_QUIET = 'quiet'
  VERBOSITY_CHOICE_INFO  = 'info'
  VERBOSITY_CHOICE_DEBUG = 'debug'

  # FIXME further constants
  #     options.fps_dcp_choices = [ 24.0, 25.0, 30.0, 48.0, 50.0, 60.0 ]
  #  options.fps_asdcp_choices = [ 23.976, 24.0, 25.0, 30.0, 48.0, 50.0, 60.0 ] # 24000/1001 not DCI compliant but shows up in asdcplib. Why?
  #  options.audio_bps_choices = [ '16', '24' ]
  #  options.dcp_kind_choices = [ 'feature', 'trailer', 'test', 'teaser', 'rating', 'advertisement', 'short', 'transitional', 'psa', 'policy' ]
  #  options.dcp_color_transform_matrix_choices = [ 'iturec709_to_xyz', 'srgb_to_xyz', '709', 'srgb', Regexp.new( '(\d+(\.\d+)?\s*){9,9}' ) ]


  
# FIXME catch missing parameters, false options, typos etc.
class Optparser
  def self.get_options
    @@options
  end
  def self.parse(args)
    # defaults
    options = OpenStruct.new
    options.output_type = OUTPUT_TYPE_CHOICE_PREVIEW
    options.output_type_choices = [ OUTPUT_TYPE_CHOICE_PREVIEW, OUTPUT_TYPE_CHOICE_FULLPREVIEW, OUTPUT_TYPE_CHOICE_DCP ]
    options.size = CONTAINER_SIZE_2K
    options.size_choices = [ CONTAINER_SIZE_2K, CONTAINER_SIZE_4K ]
    options.aspect = ASPECT_CHOICE_FLAT
    options.aspect_choices = [ ASPECT_CHOICE_FLAT, ASPECT_CHOICE_SCOPE, ASPECT_CHOICE_HD, Regexp.new( '\d+(\.\d+)?x\d+(\.\d+)?' ) ] # custom aspect ratios: match '<numeric>x<numeric>'
    options.aspect_malformed = FALSE
    options.resize = TRUE # option to _not_ resize images (useful for images which are close to target dimensions and would suffer from scaling/-resize)
    options.fps = 24.0
    options.fps_dcp_choices = [ 24.0, 25.0, 30.0, 48.0, 50.0, 60.0 ]
    options.fps_asdcp_choices = [ 23.976, 24.0, 25.0, 30.0, 48.0, 50.0, 60.0 ] # 24000/1001 not DCI compliant but shows up in asdcplib. Why?
    options.encoder = ENCODER_CHOICE_OJ
    options.encoder_choices = [ ENCODER_CHOICE_OJ_TM, ENCODER_CHOICE_OJ, ENCODER_CHOICE_KAKADU  ]
    options.output_format = 'jpg'
    options.black = 0.0
    options.black_leader = NIL
    options.black_tail = NIL
    options.audio_samplerate = SAMPLE_RATE_CHOICE_48000.to_i
    options.audio_samplerate_choices = [ SAMPLE_RATE_CHOICE_48000, SAMPLE_RATE_CHOICE_48K, SAMPLE_RATE_CHOICE_96000, SAMPLE_RATE_CHOICE_96K ]
    options.audio_bps = 24
    options.audio_bps_choices = [ '16', '24' ]
    options.dcp_title = 'Cinemaslides test'
    options.issuer = ENV[ 'USER' ] + '@' + ShellCommands::ShellCommands.hostname_command.chomp
    options.annotation = "#{ AppName } " + DateTime.now.to_s
    options.dcp_kind = 'test'
    options.dcp_kind_choices = [ 'feature', 'trailer', 'test', 'teaser', 'rating', 'advertisement', 'short', 'transitional', 'psa', 'policy' ]
    options.dcp_wrap_stereoscopic = FALSE
    options.dcp_user_output_path = nil
    options.dcp_color_transform_matrix = 'srgb_to_xyz'
    options.dcp_color_transform_matrix_choices = [ 'iturec709_to_xyz', 'srgb_to_xyz', '709', 'srgb', Regexp.new( '(\d+(\.\d+)?\s*){9,9}' ) ]
    options.dcp_encrypt = FALSE
    options.sign = FALSE
    options.kdm = FALSE
    options.kdm_cpl = NIL
    options.kdm_target = NIL
    options.kdm_start = 0 # time window will start now
    options.kdm_end = 28 # time window will be 4 weeks
    options.montage = FALSE
    options.keep = FALSE
    options.dont_check = FALSE
    options.dont_drop = FALSE
    options.verbosity = VERBOSITY_CHOICE_INFO
    options.verbosity_choices = [ VERBOSITY_CHOICE_QUIET, VERBOSITY_CHOICE_INFO, VERBOSITY_CHOICE_DEBUG ]
    options.transition_and_timing = Array.new
    options.transition_and_timing_choices = [   TRANSITION_CHOICE_CUT, TRANSITION_CHOICE_FADE, TRANSITION_CHOICE_CROSSFADE ]
    options.transition_and_timing << TRANSITION_CHOICE_CUT
    options.transition_and_timing << 5 # duration
    options.mplayer_gamma = 1.2
    
    options.input_type_choices = [ INPUT_TYPE_CHOICE_SLIDE, INPUT_TYPE_CHOICE_AV ]
    options.input_type =  INPUT_TYPE_CHOICE_SLIDE

    opts = OptionParser.new do |opts|
      opts.banner = <<BANNER
#{ AppName } #{ AppVersion } #{ ENV[ 'CINEMASLIDESDIR' ].nil? ? "\nExport CINEMASLIDESDIR to point to desired work directory needed for temporary files, thumbnails, asset depot, DCPs (Default: HOME/cinemaslidesdir)" : "\nCINEMASLIDESDIR is set (#{ ENV[ 'CINEMASLIDESDIR' ] })" } 
 
Usage: #{ File.basename( $0 ) } [--input-type <type>] [-t, --type <type>] [-k, --size <DCP resolution>] [-a, --aspect <aspect name or widthxheight>] [--dont-resize] [--fps <fps>] [-x --transition-and-timing <type,a,b[,c]>] [-j, --encoder <encoder>] [-f, --output-format <image suffix>] [-b, --black <seconds>] [--bl, --black-leader <seconds>] [--bt, --black-tail <seconds>] [-s, --samplerate <audio samplerate>] [--bps <bits per audio sample>] [--title <DCP title>] [--issuer <DCP issuer/KDM facility code>] [--annotation <DCP/KDM annotation>] [--kind <DCP kind>] [--wrap-stereoscopic] [-o, --dcp-out <path>] [-m, --montagepreview] [--mg, --mplayer-gamma <gamma>] [--keep] [--dont-check] [--dont-drop] [--sign] [--encrypt] [--kdm] [--cpl <cpl file>] [--start <days from now>] [--end <days from now] [--target <certificate>] [-v, --verbosity <level>] [--examples] [-h, --help] [ image and audio files ] [ KDM mode parameters ]

BANNER

      opts.on( '-t', '--type type', String, "Use '#{ OUTPUT_TYPE_CHOICE_PREVIEW }' (half size) or #{ 'OUTPUT_TYPE_CHOICE_FULLPREVIEW' } (full size) or #{ 'OUTPUT_TYPE_CHOICE_DCP' } (Default: preview)" ) do |p|
        if options.output_type_choices.include?( p.downcase )
          options.output_type = p.downcase
        else
          options.output_type = 'catch:' + p
        end
      end
      
      opts.on( '--input-type type',  String, "Use '#{ INPUT_TYPE_CHOICE_SLIDE }'  or '#{ INPUT_TYPE_CHOICE_AV }' (not yet implemented)" ) do |p|
        if options.input_type_choices.include?( p.downcase )
          options.input_type = p.downcase
        else
          options.input_type = 'catch:' + p
        end
      end

      
      opts.on( '-k', '--size resolution', String, "Use '#{CONTAINER_SIZE_2K}' or '#{CONTAINER_SIZE_4K}' (Default: #{CONTAINER_SIZE_2K})" ) do |p|
        if options.size_choices.include?( p.downcase )
          options.size = p.downcase
        else
          options.size = 'catch:' + p.downcase
        end
      end
      opts.on( '-a', '--aspect ratio', String, "For standard aspect ratios use '#{ASPECT_CHOICE_FLAT}', '#{ASPECT_CHOICE_SCOPE}' or '#{ASPECT_CHOICE_HD}' (Default: #{ASPECT_CHOICE_FLAT}). You can also experiment with custom aspect ratios by saying '<width>x<height>'. The numbers given will be scaled to fit into the target container (Default size or specified with '--size')." ) do |p|
        if options.aspect_choices.include?( p.downcase )
          options.aspect = p.downcase
        elsif p.match( options.aspect_choices.last )
          options.aspect = 'Custom aspect ratio:' + p
        else
          options.aspect_malformed = TRUE
        end
      end
      opts.on( '--dont-resize', 'Do not resize images (Useful for images close to target dimensions)' ) do
        options.resize = FALSE
      end
      opts.on( '--fps fps', 'Framerate (Default: 24)', Float ) do |p| # 23.976
        options.fps = p.to_f
      end
      opts.on( '-x', '--transition-and-timing transition,seconds[,seconds[,seconds]]', Array, "Use this option to specify the transition type ('#{ TRANSITION_CHOICE_CUT }', '#{ TRANSITION_CHOICE_FADE }' or '#{ TRANSITION_CHOICE_CROSSFADE }') and timing parameters (Default: '-x cut,5'). Separate parameters with comma (no spaces)" ) do |p|
        if options.transition_and_timing_choices.include?( p.first.downcase )
          options.transition_and_timing = p
        else
          options.transition_and_timing[ 0 ] = 'malformed'
        end
      end
      opts.on( '-j', '--encoder codec', String, "Use '#{ ENCODER_CHOICE_OJ }' or '#{ ENCODER_CHOICE_KAKADU }' for JPEG 2000 encoding (Default: openjpeg)" ) do |p|
        options.encoder = p.downcase
      end
      opts.on( '-f', '--output-format suffix', String, "Use 'jpg' or any other image related suffix (Default: jpg for previews, tiff for DCPs)" ) do |p|
        options.output_format = p
      end
      opts.on( '-b', '--black seconds', Float, 'Length of black leader and tail (Default: 0)' ) do |p|
        options.black = p
      end
      opts.on( '--bl', '--black-leader seconds', Float, 'Length of black leader (Default: 0)' ) do |p|
        options.black_leader = p
      end
      opts.on( '--bt', '--black-tail seconds', Float, 'Length of black tail (Default: 0)' ) do |p|
        options.black_tail = p
      end
      opts.on( '-r', '--samplerate rate', String, "Audio samplerate. Use '#{SAMPLE_RATE_CHOICE_48000}', '#{SAMPLE_RATE_CHOICE_48K}', '#{SAMPLE_RATE_CHOICE_96000}' or '#{SAMPLE_RATE_CHOICE_96K}' (Default: #{SAMPLE_RATE_CHOICE_48000})" ) do |p|
        if options.audio_samplerate_choices.include?( p.downcase )
          case p.downcase
          when SAMPLE_RATE_CHOICE_48000, SAMPLE_RATE_CHOICE_48K
            options.audio_samplerate = SAMPLE_RATE_CHOICE_48000.to_i
          when SAMPLE_RATE_CHOICE_96000, SAMPLE_RATE_CHOICE_96K
            options.audio_samplerate = SAMPLE_RATE_CHOICE_96000.to_i
          end
        end
      end
      opts.on( '--bps bps', Integer, "Bits per audio sample. Use '16' or '24' (Default: 24)" ) do |p|
        if options.audio_bps_choices.include?( p )
          options.audio_bps = p
        end
      end
      opts.on( '--title title', String, 'DCP content title' ) do |p|
        options.dcp_title = p
      end
      opts.on( '--issuer issuer', String, 'DCP/KDM issuer. In KDM mode the first 3 letters will be used to signify the KDM creation facility, following KDM naming conventions.' ) do |p|
        options.issuer = p
      end
      opts.on( '--annotation annotation', String, 'DCP/KDM annotation' ) do |p|
        options.annotation = p
      end
      opts.on( '--kind kind', "DCP content kind. Use 'feature', 'trailer, 'test', 'teaser', 'rating', 'advertisement', 'short', 'transitional', 'psa' or 'policy' (Default: test)" ) do |p|
        if options.dcp_kind_choices.include?( p.downcase )
          options.dcp_kind = p.downcase
        end
      end
      opts.on( '--wrap-stereoscopic', 'Wrap images as stereoscopic essence (Useful when a monoscopic slideshow needs to run on a 3D projector preset)' ) do
        options.dcp_wrap_stereoscopic = TRUE
      end
      opts.on( '-o', '--dcp-out path', String, 'DCP location and folder name (Full path. Default: Write to working directory)' ) do |p|
        options.dcp_user_output_path = p
      end
      opts.on( '-m', '--montagepreview', 'Display a montage of the images before processing' ) do
        options.montage = TRUE
      end
      opts.on( '--mg', '--mplayer-gamma gamma', Float, 'Tweak mplayer gamma (Used for previews. Range 0.1 - 10. Default: 1.2)' ) do |p|
        options.mplayer_gamma = p if ( 0.1 <= p and p <= 10 )
      end
      opts.on( '--keep', 'Do not remove preview/temporary files' ) do
        options.keep = TRUE
      end
      opts.on( '--dont-check', 'Do not check files' ) do
        options.dont_check = TRUE
      end
      opts.on( '--dont-drop', 'Do not drop and ignore unreadable files or files ImageMagick cannot decode but nag and exit instead' ) do
        options.dont_drop = TRUE
      end
      opts.on( '--sign', 'Sign CPL and PKL (cinemaslides has a directory that holds the signing certificate and validating certificate chain, not changeable so far)' ) do
        options.sign = TRUE
      end
      opts.on( '--encrypt', 'Encrypt trackfiles. Implies signature. Stores content keys in CINEMASLIDESDIR/keys' ) do
        options.dcp_encrypt = TRUE
	options.sign = TRUE
      end
      opts.on( '--kdm', 'KDM mode: Generate key delivery message. Use with --cpl, --start, --end, --issuer and --target' ) do
        options.kdm = TRUE
	options.output_type = OUTPUT_TYPE_CHOICE_KDM
      end
      opts.on( '--cpl <file>', String, 'KDM mode: Specify CPL file' ) do |p|
        options.kdm_cpl = p
      end
      opts.on( '--start <days>', Integer, 'KDM mode: KDM validity starts <days> from now (Default: Now)' ) do |p|
        options.kdm_start = p
      end
      opts.on( '--end <days>', Integer, 'KDM mode: KDM validity ends <days> from now (Default: 4 weeks from now)' ) do |p|
        options.kdm_end = p
      end
      opts.on( '--target <certificate>', String, 'KDM mode: Path to the recipient device certificate' ) do |p|
        options.kdm_target = p
      end
      opts.on( '-v', '--verbosity level', String, "Use '#{ VERBOSITY_CHOICE_QUIET }', '#{ VERBOSITY_CHOICE_INFO }' or '#{ VERBOSITY_CHOICE_DEBUG }' (Default: #{ VERBOSITY_CHOICE_INFO })" ) do |p|
        if options.verbosity_choices.include?( p )
          options.verbosity = p
        else
          options.verbosity = "info"
        end
      end

      opts.on( '--examples', 'Some examples and explanations' ) do
        app = File.basename( $0 )
        examples = <<EXAMPLES
#{ AppName } #{ AppVersion }

Specify options in any order. Order of image/audio files matters. Audio is optional.
Audio timing is handled in a first-come, first-served manner -- independently from image timings

In order to use signature and KDM generation cinemaslides comes with 3 related, digital cinema compliant
certificates  (#{ app } needs some specific names for now -- #{ AppVersion })
(these are created with https://github.com/wolfgangw/digital_cinema_tools/blob/master/make-dc-certificate-chain.rb )

  Preview slideshow with audio (Half sized preview. Cut transition. Default duration: 5 seconds each):
$ #{ app } image1.jpg audio.wav image2.tiff

  Preview slideshow with audio (Full sized preview. Transition: crossfades for 1 second, 20 seconds at full level each):
$ #{ app } --type fullpreview -x crossfade,1,20 image1.tiff image2.ppm audio1.wav audio2.wav

  Create slideshow DCP, use all image files in directory 'slides' (Resolution: 2K. 5 seconds black leader):
$ #{ app } --type dcp --size 2k --black-leader 5 slides/*

  Create slideshow DCP (Preview thumbnails. Aspect ratio: scope):
$ #{ app } audio.wav *.tiff --montagepreview --aspect scope -t dcp --title 'Slideshow Test' --issuer 'Facility'

  Transition: fade in for 0.5 seconds, hold for 10, fade out for 4
$ #{ app } -x fade,0.5,10,4 ...

  Carousel goes berserk (note option --dont-check in order to avoid extensive checks for lots of images)
$ #{ app } -t dcp --title "Motion sequence" --fps 24 -x cut,0.04167 --dont-check motion_sequence/

  Write DCP to custom location
$ #{ app } --dcp-out /media/usb-disk/slideshow --type dcp image.tiff audio.wav --title "First composition"

  Write another composition to the same custom location (PKL and ASSETMAP will be extended)
$ #{ app } -o /media/usb-disk/slideshow -t dcp image2.tiff image3.tiff song.wav --title "Another composition"

  Timings are global. Some workaround kind of finer-grained timing control:
$ #{ app } -x cut,3    title title title 1st_slide 2nd_slide credits credits

  Slideshow of your truetype fonts:
$ #{ app } -x crossfade,2,2 `find /usr/share/fonts/truetype/ -name '*ttf' -type f`

  Custom aspect ratios (Work fine on a Solo G3, what about other servers?):
$ #{ app } --aspect 1.33x1 | --aspect 3072x2304 | --aspect 3x1 [...]

  Encrypt DCP trackfiles and store content keys in $CINEMASLIDESDIR/keys (--encrypt implies signing):
  Go check the final CPL for key IDs and compare to stored content keys
  Using asdcplib you can decrypt and extract essence with
        asdcp-test -x decrypted_ -k '<content key -- 16 bytes in hex>' <encrypted MXF>
$ #{ app } -t dcp --encrypt --title "Encryption test" -o ENCRYPTION_TST_F_2K_20101231_WOE_OV -x cut,0.04167 demo_sequence/

  Generate KDM for some content, targeting our XDC Solo G3 server certificate with a time window from now to 10 days from now:
$ #{ app } -v debug --kdm --cpl ENCRYPTION_TST_F_2K_20101231_WOE_OV/cpl_<UUID>_.xml --start 0 --end 10 --target 200100400530_000487.pem

EXAMPLES
        puts examples
        exit
      end
      opts.on_tail( '-h', '--help', 'Display this screen' ) do
        puts opts
        exit
      end

    end
    opts.parse!(args)
    
    @@options = options
    options
  end # parse
  
  def self.set_black_options
     @@options.black_leader =  @@options.black_tail = @@options.black
     @@options.black_leader = @@options.black_leader.abs unless @@options.black_leader.nil?
     @@options.black_tail = @@options.black_tail.abs unless @@options.black_tail.nil?
  end
  
  def self.set_size
    if @@options.output_type ==  OUTPUT_TYPE_CHOICE_PREVIEW
      @@options.size = '1k'
    end
  end

  def self.aspect_option_ok?
    logger = Logger::Logger.instance
    if @@options.aspect_malformed
      logger.info( "Malformed aspect ratio. Use #{ @@options.aspect_choices[ 0, @@options.aspect_choices.size - 1 ].join( ', ' ) } or <width>x<height>" )
      return FALSE
    else
      w, h = @@options.aspect.split( 'Custom aspect ratio: ' ).last.match( @@options.aspect_choices.last ).to_s.split( 'x' )
      if ! h.nil?
	if w.to_f == 0 or h.to_f == 0
	  logger.info( "Zero in aspect ratio specs. Doesn't compute" )
	  return FALSE
	end
      end
    end
    TRUE
  end
  
  def self.size_option_ok?
    logger = Logger::Logger.instance
    m = @@options.size.match( /catch:(.*)/ )
    unless m.nil?
      if [ 'eep', 'ind', 'dm' ].include?( m[1] ) # yeah, ugh, catch keep, kind, kdm
	logger.info( "Sorry for being fussy here, but did you mean to say '--k#{ m[ 1 ] }'? Option parser bailout" )
      else
	logger.info( "Can't understand -k's argument: '#{ m[ 1 ] }'. Use #{ @@options.size_choices.join( ' or ' ) }" )
      end
      return FALSE
    end
    TRUE
  end
  
  def self.output_type_option_ok?
    logger = Logger::Logger.instance
    m = @@options.output_type.match( /catch:(.*)/ )
    unless m.nil?
      logger.info( "Specify output type: preview, fullpreview or dcp" )
      return FALSE
    end
    TRUE
  end

  def self.input_type_option_ok?
    logger = Logger::Logger.instance
    m = @@options.input_type.match( /catch:(.*)/ )
    unless m.nil?
      logger.info( "Specify input type: slideshow or avcontainer" )
      return FALSE
    end
    TRUE
  end

  def self.dcp_related_options_ok?
    logger = Logger::Logger.instance
    # check dcp related @options
    if @@options.output_type == "dcp"
      unless @@options.encoder_choices.include?( @@options.encoder )
	logger.critical( "Not a usable encoder: '#{ @@options.encoder }'" )
	return FALSE
      end
            
      if ! @@options.fps_dcp_choices.include?( @@options.fps )
	if @@options.fps_asdcp_choices.include?( @@options.fps )
	  logger.critical( "DCI compliant framerate but not yet implemented in #{ File.basename( $0 ) }: #{ @@options.fps } fps" )
	else
	  logger.critical( "Not a DCI compliant framerate: #{ @@options.fps } fps" )
	end
	return FALSE
      end
      logger.debug( "DCP related @options ok" )
    end
    TRUE
  end

  def self.set_and_check_fps_option
    logger = Logger::Logger.instance
    if @@options.output_type == 'dcp' and @@options.dcp_wrap_stereoscopic and @@options.fps != 24
      logger.info( "Option '--wrap-stereoscopic' is set -> Setting fps to 24" )
      @@options.fps = 24.0
    end
  end

  def self.set_and_check_transition_and_timing_option?
    # check @options.transition_and_timing
    logger = Logger::Logger.instance
    @@options.transition_and_timing.first.downcase!
    if @@options.transition_and_timing.first == TRANSITION_CHOICE_FADE and @@options.transition_and_timing.length == 4
      @@options.fade_in_time = @@options.transition_and_timing[1].to_f
      @@options.duration = @@options.transition_and_timing[2].to_f
      @@options.fade_out_time = @@options.transition_and_timing[3].to_f
    elsif @@options.transition_and_timing.first == TRANSITION_CHOICE_CUT and @@options.transition_and_timing.length == 2
      @@options.fade_in_time = 0
      @@options.duration = @@options.transition_and_timing[1].to_f
      @@options.fade_out_time = 0
    elsif @@options.transition_and_timing.first == TRANSITION_CHOICE_CROSSFADE and @@options.transition_and_timing.length == 3
      @@options.crossfade_time = @@options.transition_and_timing[1].to_f
      @@options.duration = @@options.transition_and_timing[2].to_f
    else
      logger.warn( "Malformed transition and timing specs" )
      logger.info( "Use '-x fade,a,b,c' or '-x crossfade,a,b' or '-x cut,b' (a = fade in time/crossfade time, b = full level time, c = fade out time)" )
      return FALSE
    end
    TRUE
  end
  
  def self.set_output_format_option
    if @@options.output_type == "dcp"
      @@options.output_format = "tiff"
    end
  end

  def self.set_dcpdir_option( dcpdir )
    if @@options.dcp_user_output_path == nil
      @@options.dcpdir = dcpdir
    else
      @@options.dcpdir = @@options.dcp_user_output_path
    end
  end

  
end # class




end