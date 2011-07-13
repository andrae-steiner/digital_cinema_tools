module Asset
  
  require 'ShellCommands'
  require 'Logger'
  require 'CinemaslidesCommon'
  
  ShellCommands = ShellCommands::ShellCommands
  
  class AssetFunctions
    def initialize(output_type_obj)
      @output_type_obj = output_type_obj
      @logger = Logger::Logger.instance
      @asset_mutexes = Hash.new
      @check_asset_mutex = Mutex.new
      @digests = Hash.new
    end
            
    def create_asset( filename_s,  suffix, level = nil , &block)
      return create_asset_2( filename_s,  suffix, filename_to_asset_conversion_proc, level  , &block)
    end
        
    def do_synchronized( image,  &block)
      if !@asset_mutexes.has_key?(image)
	@logger.info("T #{ Thread.current[:id] }: no key for @asset_functions.asset_mutexes[\"#{ image }\"]. This should not happen. Exiting")
	exit
      end
      yield if block_given? 
    end
    
    private
    
    def filename_to_asset_conversion_proc
      raise NotImplementedError, "Do not instanciate this abstract class: #{self.class}"
    end

    # asset match is based on a /conform's/ IM signature + dimensions + (level unless jpeg 2000 codestream requested) + (jpeg2000_codec + fps if jpeg 2000 codestream is requested) + suffix
    # not any more, because this is soooo time consuming
    def create_asset_2( filename_s,  suffix, filename_to_asset_conversion_proc, level = nil , &block)
      asset = ""; todo = TRUE
      @check_asset_mutex.synchronize do	
	asset, origin = filename_to_asset_conversion_proc.call( filename_s, suffix, level)
	todo = !File.exists?( asset )
	@logger.debug( "T #{Thread.current[:id]}:asset = #{asset}")
	@logger.debug( "T #{Thread.current[:id]}:todo  = #{todo}")
	if !todo
	      @logger.debug( "T #{Thread.current[:id]}: Skip: Asset exists (#{ origin } -> #{ File.basename( asset ) })" )
	end
	@asset_mutexes[asset] = Mutex.new unless @asset_mutexes.has_key?(asset)
      end
      @asset_mutexes[asset].synchronize do
	if todo
	  yield asset
	end
      end
      return asset
    end

    # TAKE CARE: for different content with the filename
    # you get the same hash. But this happens only if during a run of cinemaslides
    # the content of a file is altered between calls to digest_over_content. Therefore
    # the test.
    def digest_over_content( file )
      if @digests.has_key?(file)
	id = @digests[ file ][ 0 ]
	t  = @digests[ file ][ 1 ]
	if (t <=> File.mtime( file ) ) != 0
	  @logger.info("Fatal: content of \"#{ file }\" has been changed between calls of Asset::digest_over_content. Exiting. ")
	  exit
	end
	id = @digests[ file ][ 0 ]
      else
	id = Digest::MD5.hexdigest( File.read( file ) )
	@digests[ file ] = [ id, File.mtime( file ) ]
      end
      return id
    end
    def digest_over_file_basename( file )
      Digest::MD5.hexdigest( File.basename( file ) )
    end
    def digest_over_string( s )
      Digest::MD5.hexdigest( s )
    end
    # Thanks Wolfgang
    # entry into the asset depot will trigger a relatively strong and good enough md5 digest over content
    # members of the asset depot will trigger a cheaper and good enough digest over filename (which is in part an md5 digest)
    #   + dimensions + (level unless jpeg 2000 codestream requested) + (encoder + fps if jpeg 2000 codestream is requested) + suffix
    # BEWARE Cheap hash  does not work for audio assets
    def filename_hash2( file)
      expanded_assetsdir = File.expand_path(@output_type_obj.assetsdir)
      if File.expand_path(File.dirname( file )) != expanded_assetsdir 
        digest_over_content( file )
      else
        digest_over_file_basename( file )
      end
    end
            
  end
  
  class AVSequenceAssetFunctions < AssetFunctions
    def initialize( output_type_obj, av_input_fps = 24, av_output_image_suffix = 'png' )
      super( output_type_obj )
      @av_input_fps = av_input_fps
      @av_output_image_suffix = av_output_image_suffix
    end
    def create_asset( filename_s,  suffix, level = nil , &block)
      raise NotImplementedError, "Do not call this method."
    end
    def create_video_asset( filename, &block)
      return create_asset_2( filename, "", filename_to_video_asset_conversion_proc, nil, &block )
    end
    def create_audio_asset( filename, &block)
      return create_asset_2( filename , CinemaslidesCommon::FILE_SUFFIX_PCM, filename_to_audio_asset_conversion_proc, nil, &block )
    end
    
    private
    
    def filename_to_video_asset_conversion_proc
      Proc.new do |filename, suffix, level |
	id = digest_over_content( filename )
	origin = File.basename( filename )
	assetname = File.join( @output_type_obj.assetsdir, "from_av_video_" + id + "_#{ @av_input_fps }_#{ @av_output_image_suffix }" )
	assetname, origin = assetname, origin
      end
    end
    def filename_to_audio_asset_conversion_proc
      Proc.new do |filename, suffix, level |
	id = digest_over_content( filename )
	origin = File.basename( filename )
	assetname = File.join( @output_type_obj.assetsdir, "from_av_audio_" + id + suffix )
	assetname, origin = assetname, origin
      end
    end
  end
  
  class AudioAssetfunctions < AssetFunctions
    def initialize(output_type_obj, samplerate, bps, channelcount )
      super(output_type_obj)
      @samplerate = samplerate 
      @bps = bps
      @channelcount = channelcount
    end
    
    def create_silence_asset( suffix, seconds, level = nil, &block )
      suffix2 = seconds.to_s + '_' + @samplerate.to_s + '_' + @bps.to_s + '_' + @channelcount.to_s + suffix 
      return create_asset_2( CinemaslidesCommon::SILENCE_FILENAME_PREFIX, suffix2, simple_conversion_proc, level, &block)
    end
    
    def create_sequence_audio_asset (conformed_audio_list, image_sequence_length_seconds, suffix, &block )
      set = Array.new
      conformed_audio_list.each do |e|
	set << File.basename( e )
      end
      filename = "#{ digest_over_string( set.join ) }"
      suffix2 = "_sequence_#{ image_sequence_length_seconds }#{ suffix }"
      return create_asset_2( filename, suffix2, simple_conversion_proc, nil, &block )
    end
    
    private
    def simple_conversion_proc
      Proc.new do |filename_s, suffix, level |
	assetname = File.join( @output_type_obj.assetsdir_audio, filename_s + suffix )
	origin = filename_s
	assetname, origin = assetname, origin
      end
    end
    def filename_to_asset_conversion_proc
      Proc.new do |filename_s, suffix, level |
	hexdigest = digest_over_content( filename_s )
	assetname = File.join( @output_type_obj.assetsdir_audio, "#{ hexdigest }_#{ @samplerate }_#{ @bps }_#{ @channelcount }#{suffix}" )
	origin = File.basename( filename_s )
	assetname, origin = assetname, origin
      end
    end
  end
  
  class ImageAssetFunctions < AssetFunctions
    def initialize(output_type_obj, resize)
      super(output_type_obj)
      @resize = resize
    end
    def create_black_asset( suffix, &block )
      return create_asset( CinemaslidesCommon::FILENAME_BLACK_FRAME, suffix,  level, &block )
    end
    private
    def filename_to_asset_conversion_proc
      Proc.new do |filename_s, suffix, level |
	# 2 images from crossfade?
	if filename_s.size == 2
	  id = filename_hash2( filename_s[0]) + '_' + filename_hash2( filename_s[1])
	  origin = [ File.basename( filename_s[ 0 ] ), File.basename( filename_s[ 1 ] ) ].join( ' X ' )
	else # not from crossfade
	  id = File.exists?( filename_s ) ? filename_hash2( filename_s) :  CinemaslidesCommon::FILENAME_BLACK_FRAME   
	  origin = File.basename( filename_s )
	end
	assetname = File.join( @output_type_obj.assetsdir, id + "_#{ @output_type_obj.dimensions }_#{ @resize ? 'r' : 'nr' }#{ level.nil? ? '' : '_' + level.to_s }#{ @output_type_obj.asset_suffix(suffix) }" )
	assetname, origin = assetname, origin
      end
    end

  end
  
  class ThumbAssetFunctions < AssetFunctions
    def create_montage_asset( filename_s, suffix, level = nil, &block )
      return create_asset_2( filename_s, suffix, filename_to_montage_asset_conversion_proc, level, &block )
    end    
    private 
    def filename_to_montage_asset_conversion_proc
      Proc.new do |filename_s, suffix, level |
	assetname = File.join( @output_type_obj.thumbsdir, Digest::MD5.hexdigest( filename_s ) + "_#{ @output_type_obj.thumbs_dimensions }_" + CinemaslidesCommon::MONTAGE_FILENAME_SUFFIX + suffix )
	origin = File.basename( filename_s )
	assetname, origin = assetname, origin
      end
    end
    def filename_to_asset_conversion_proc
      Proc.new do |filename_s, suffix, level |
	assetname = File.join( @output_type_obj.thumbsdir, Digest::MD5.hexdigest(File.read( filename_s )) + "_#{ @output_type_obj.thumbs_dimensions }_" + suffix )
	origin = File.basename( filename_s )
	assetname, origin = assetname, origin
      end
    end
  end
  

end