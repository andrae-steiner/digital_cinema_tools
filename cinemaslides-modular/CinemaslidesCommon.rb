module CinemaslidesCommon
  require 'Logger'
  
# from OptParser
  OUTPUT_TYPE_CHOICE_PREVIEW = 'preview'
  OUTPUT_TYPE_CHOICE_FULLPREVIEW = 'fullpreview'
  OUTPUT_TYPE_CHOICE_DCP = 'dcp' 
  OUTPUT_TYPE_CHOICE_SMPTE_DCP_NORM = 'smpte-dcp' 
  OUTPUT_TYPE_CHOICE_MXF_INTEROP_DCP_NORM = 'mxf-interop-dcp' 
  OUTPUT_TYPE_CHOICE_NO_DCP_NORM = 'none-dcp' 
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
  ASPECT_CHOICE_CUSTOM_PREFIX = 'Custom aspect ratio:'
  ASPECT_CHOICES = [ASPECT_CHOICE_FLAT, ASPECT_CHOICE_SCOPE, ASPECT_CHOICE_HD]
  SAMPLE_RATE_CHOICE_48000 = '48000'
  SAMPLE_RATE_CHOICE_48K   = '48k'
  SAMPLE_RATE_CHOICE_96000 = '96000'
  SAMPLE_RATE_CHOICE_96K   = '96k'
  DCP_KIND_FEATURE      = 'feature'
  DCP_KIND_TRAILER      = 'trailer'
  DCP_KIND_TEST         = 'test'
  DCP_KIND_TEASER       = 'teaser'
  DCP_KIND_RATING       = 'rating'
  DCP_KIND_ADVERTISMENT = 'advertisement'
  DCP_KIND_SHORT        = 'short'
  DCP_KIND_TRANSITIONAL = 'transitional'
  DCP_KIND_PSA          = 'psa'
  DCP_KIND_POLICY       = 'policy'
  DCP_TITLE = 'Cinemaslides test'
  FPS_DCP_CHOICES = [ 24.0, 25.0, 30.0, 48.0, 50.0, 60.0 ]
  FPS_ASDCP_CHOICES = [ 23.976, 24.0, 25.0, 30.0, 48.0, 50.0, 60.0 ] # 24000/1001 not DCI compliant but shows up in asdcplib. Why?
  AUDIO_BPS_16 = '16'
  AUDIO_BPS_24 = '24'
# from OptParser
  
# from Asset
  FILENAME_BLACK_FRAME = "black"
  MONTAGE_FILENAME_SUFFIX = "montage_"
  SILENCE_FILENAME_PREFIX = "silence_"
# from Asset
  
# from Audiosequence
    FILE_SUFFIX_PCM = ".wav"
# from Audiosequence

# from DCP
  MAIN_PICTURE_ASSET_TYPE ='MainPicture'
  MAIN_STEREOSCOPIC_PICTURE_ASSET_TYPE = 'MainStereoscopicPicture'
  MAIN_SOUND_ASSET_TYPE = 'MainSound'
  MAIN_SUBTITLE_ASSET_TYPE = 'MainSubtitle'
  CPL_ASSET_TYPES = [ MAIN_PICTURE_ASSET_TYPE, MAIN_STEREOSCOPIC_PICTURE_ASSET_TYPE, MAIN_SOUND_ASSET_TYPE, MAIN_SUBTITLE_ASSET_TYPE ]
  MIMETYPE_MXF = "application/mxf"
  MIMETYPE_XML = "text/xml"
  MIMETYPE_TTF = "application/x-font-ttf"
# from DCP
  
# from Encoder
  DCP_MAX_BPS = 250000000
# from Encoder

# from ImageSequence
  THUMBFILE_SUFFIX = ".jpg"
  FILE_SEQUENCE_FORMAT = "%06d"
# from ImageSequence

# from InputType
   AUDIOSUFFIX_REGEXP = Regexp.new(/(mp3|MP3|wav|WAV|flac|FLAC|aiff|AIFF|aif|AIF|ogg|OGG)$/)
# from InputType

# from DM_SMPTE_430_1_2006
  KEYTYPE_MDIK = 'MDIK'
  KEYTYPE_MDAK = 'MDAK'
  KEYTYPE_MDSK = 'MDSK'
# from KDM_SMPTE_430_1_2006
  
# from Logger
  VERBOSITY_CHOICE_QUIET = 'quiet'
  VERBOSITY_CHOICE_INFO  = 'info'
  VERBOSITY_CHOICE_DEBUG = 'debug'
# from Logger

# from OutputType
  TESTING = FALSE
  ASPECT_CONTAINER = 'container'  
  SRGB_TO_XYZ = "0.4124564 0.3575761 0.1804375 0.2126729 0.7151522 0.0721750 0.0193339 0.1191920 0.9503041"
  ITUREC709_TO_XYZ = "0.412390799265959  0.357584339383878  0.180480788401834 0.21263900587151 0.715168678767756 0.0721923153607337 0.0193308187155918 0.119194779794626 0.950532152249661"
  THUMB_DIMENSIONS_FACTOR = 6
# from OutputType
   
# from MXF  
  MXF_KEYS_ASSETUUID            = 'AssetUUID' 
  MXF_KEYS_CONTAINER_DURATION   = 'ContainerDuration' 
  MXF_KEYS_CRYPTOGRAPHIC_KEY_ID = 'CryptographicKeyID'
  MXF_KEYS_SAMPLE_RATE          = 'SampleRate'
  MXF_KEYS_EDIT_RATE            = 'EditRate'
  MXF_KEYS_ASPECT_RATIO         = 'AspectRatio'
  MXF_KEYS_STEREOSCOPIC         = 'File essence type is JPEG 2000 stereoscopic pictures.'
  MXF_KEYS_STOREDWIDTH          = 'StoredWidth'
  MXF_KEYS_STOREDHEIGHT         = 'StoredHeight'
# from MXF  

  # calculate indices of array source for multithreading
  # so that  source can be divided into equal parts and be
  # fed into the threads
  def CinemaslidesCommon::split_indices(source)
    logger = Logger::Logger.instance
    n_threads = OptParser::Optparser.get_options.n_threads
    indices = Array.new
    n_elements = source.length/n_threads
    remainder = source.length%n_threads      
    if (n_elements == 0) 
      remainder.times do |i|
	indices << [i,i]
      end
    else
      len2 = source.length+n_threads-1
      (n_threads-remainder).times do |i|
	start_index = i*(len2/n_threads)
	end_index   = (i == (n_threads - 1)) ? source.length - 1 : (i + 1)*(len2/n_threads) - 1
	indices << [start_index, end_index]
      end
      remainder.times do |i|
	f = i + n_threads-remainder
	start_index = f*(len2/n_threads) - i
	end_index   = (f == (n_threads - 1)) ? source.length - 1 : (f + 1)*(len2/n_threads) - 1 - (i + 1)
	indices << [start_index, end_index]
      end
    end
    return indices
  end

  def CinemaslidesCommon::process_elements_multithreaded( source, &block )
    threads = Array.new
    indices = CinemaslidesCommon::split_indices(source)
    # start the threads
    indices.length.times do |thread_i|
      threads << Thread.new do
	yield thread_i, indices
      end  #       Thread.new do
    end # indices.length.times do |thread_i|
    threads.each {|t| t.join()}
    return threads
  end

  
end
