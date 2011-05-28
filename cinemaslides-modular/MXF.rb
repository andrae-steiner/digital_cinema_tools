module MXF
  
  require 'Logger'
  require 'ShellCommands'
  require 'KDM_SMPTE_430_1_2006'
  ShellCommands = ShellCommands::ShellCommands
  
  MXF_KEYS_ASSETUUID            = 'AssetUUID' 
  MXF_KEYS_CONTAINER_DURATION   = 'ContainerDuration' 
  MXF_KEYS_CRYPTOGRAPHIC_KEY_ID = 'CryptographicKeyID'
  MXF_KEYS_SAMPLE_RATE          = 'SampleRate'
  MXF_KEYS_EDIT_RATE            = 'EditRate'
  MXF_KEYS_ASPECT_RATIO         = 'AspectRatio'
  MXF_KEYS_STEREOSCOPIC         = 'File essence type is JPEG 2000 stereoscopic pictures.'
  MXF_KEYS_STOREDWIDTH          = 'StoredWidth'
  MXF_KEYS_STOREDHEIGHT         = 'StoredHeight'

  
  
  class MXF_Metadata < Hash
    def initialize( mxf )
      asdcp_info = ShellCommands.asdcp_test_v_i_command( mxf ).chomp
      if asdcp_info =~ /File essence type is JPEG 2000/ # ... (stereoscopic)? pictures
	asdcp_info = asdcp_info.split( /\n-- JPEG 2000 Metadata --/ ).first
      end
      asdcp_info = asdcp_info.split( /\n\s*/ )
      @meta = Hash.new
      asdcp_info.each do |line|
	key, value = line.split( ': ' )
	@meta[ key ] = value
      end
    end # initialize
    
    def hash
      @meta
    end
  end # MXF_Metadata

  class MXFTrack
    attr_reader :mxf_file_name, :mxf_uuid
    def initialize(prefix, keyshortcut,
                   dcpdir, keysdir, stereoscopic, dcp_encrypt, fps, dcp_functions)
      # Generate content keys. Proof-of-concept, ad-hoc, hairy, you name it.
      @dcp_functions = dcp_functions
      @mxf_uuid =  ShellCommands.uuid_gen
      @mxf_file_name =  File.join( dcpdir, prefix + "_#{ mxf_uuid }_.mxf" )
      @key = ShellCommands.random_128_bit
      @key_id = ShellCommands.uuid_gen
      @logger = Logger::Logger.instance
      @keyshortcut = keyshortcut
      @steroscopic = stereoscopic
      @dcpdir = dcpdir
      @dcp_encrypt = dcp_encrypt
      @fps = fps
      write_key(keysdir) if dcp_encrypt
    end
    
    def write_asdcp_track( file )
      if @stereoscopic
	@logger.info( 'Wrap as stereoscopic essence' )
      end
      opts_params_args = "#{ @dcp_functions.mxf_UL_value_option } #{ @dcp_encrypt ? '-e -k ' + @key + ' -j ' + @key_id : '-E' } -p #{ @fps } -a #{ @mxf_uuid } -c #{ @mxf_file_name } #{ @stereoscopic ? '-3 ' + file : ''  } #{ file }"
      ShellCommands.asdcp_test_create_mxf( opts_params_args )
    end
    
    private 
    
   def write_key(dir)
      File.open( File.join( dir, @key_id ), 'w' ) { |f| f.write( @key_id + ':' + @keyshortcut + ':' + @key ) }
    end
    
  end
  
  class AudioMXFTrack < MXFTrack
    def initialize(dcpdir, keysdir, dcp_encrypt, fps, dcp_functions)
      super("pcm", KDM_SMPTE_430_1_2006::KEYTYPE_MDAK,
                   dcpdir, keysdir, FALSE, dcp_encrypt, fps, dcp_functions)
    end
  end
  
  class VideoMXFTrack < MXFTrack
    def initialize(dcpdir, keysdir, steroscopic, dcp_encrypt, fps, dcp_functions)
      super(dcp_functions.dcp_image_sequence_basename, KDM_SMPTE_430_1_2006::KEYTYPE_MDIK, dcpdir, keysdir, steroscopic, dcp_encrypt, fps, dcp_functions)
    end
  end

end # module MXF
