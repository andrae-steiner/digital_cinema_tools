module MXF
  
  require 'Logger'
  require 'ShellCommands'
  require 'CinemaslidesCommon'
  
  ShellCommands = ShellCommands::ShellCommands
  
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
    @@asdcp_call_count = 0
    attr_reader :mxf_file_name, :mxf_uuid
    def initialize(prefix, keyshortcut,
                   dcpdir, keysdir, wrap_stereo_or_3D, dcp_encrypt, fps, dcp_functions)
      # Generate content keys. Proof-of-concept, ad-hoc, hairy, you name it.
      @dcp_functions = dcp_functions
      @mxf_uuid =  ShellCommands.uuid_gen
      @mxf_file_name =  File.join( dcpdir, prefix + "_#{ mxf_uuid }_.mxf" )
      @key = ShellCommands.random_128_bit
      @key_id = ShellCommands.uuid_gen
      @logger = Logger::Logger.instance
      @keyshortcut = keyshortcut
      @wrap_stereo_or_3D = wrap_stereo_or_3D
      @dcpdir = dcpdir
      @dcp_encrypt = dcp_encrypt
      @fps = fps
      write_key(keysdir) if dcp_encrypt
    end
    
    def write_asdcp_track( file_par )
      opts_params_args = "#{ @dcp_functions.mxf_UL_value_option } #{ @dcp_encrypt ? '-e -k ' + @key + ' -j ' + @key_id : '-E' } -p #{ @fps } -a #{ @mxf_uuid } -c #{ @mxf_file_name } #{ file_par } "
      ShellCommands.asdcp_test_create_mxf( opts_params_args )
      @logger.debug( "Thread #{Thread.current}: MXFTrack.write_asdcp_track stop " )
    end
    
    private 
    
   def write_key(dir)
      File.open( File.join( dir, @key_id ), 'w' ) { |f| f.write( @key_id + ':' + @keyshortcut + ':' + @key ) }
    end
    
  end
  
  class AudioMXFTrack < MXFTrack
    def initialize(dcpdir, keysdir, dcp_encrypt, fps, dcp_functions)
      super(CinemaslidesCommon::MXF_AUDIO_FILE_PREFIX, CinemaslidesCommon::KEYTYPE_MDAK,
                   dcpdir, keysdir, FALSE, dcp_encrypt, fps, dcp_functions)
    end
  end
  
  class VideoMXFTrack < MXFTrack
    def initialize(dcpdir, keysdir, stereoscopic, dcp_encrypt, fps, dcp_functions)
      super(dcp_functions.dcp_image_sequence_basename, CinemaslidesCommon::KEYTYPE_MDIK, dcpdir, keysdir, stereoscopic, dcp_encrypt, fps, dcp_functions)
    end
    def write_asdcp_track( file_s )
      @logger.debug( "Thread #{Thread.current}: VideoMXFTrack.write_asdcp_track start " )
      super( @wrap_stereo_or_3D ? "-3 #{file_s[0]}  #{file_s[1]}" : file_s ) 
      if @wrap_stereo_or_3D
	@logger.info( 'Wrap as stereoscopic essence or 3D' )
      end
      @logger.debug( "Thread #{Thread.current}: VideoMXFTrack.write_asdcp_track stop " )
    end
  end

end # module MXF
