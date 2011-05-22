module Asset
  
  require 'ShellCommands'
  require 'Logger'
  
  ShellCommands = ShellCommands::ShellCommands

  FILENAME_BLACK_FRAME = "black"
  MONTAGE_FILENAME_SUFFIX = "montage_"
  SILENCE_FILENAME_PREFIX = "silence_"
  
  
  class AssetFunctions
    def initialize(output_type_obj)
      @output_type_obj = output_type_obj
      @logger = Logger::Logger.instance
    end
    
    # asset match is based on a /conform's/ IM signature + dimensions + (level unless jpeg 2000 codestream requested) + (jpeg2000_codec + fps if jpeg 2000 codestream is requested) + suffix
    # not any more, because this is soooo time consuming
    def check_for_asset( filename_s, suffix, level = nil )
      check_for_asset_2( filename_s, suffix, filename_to_asset_conversion_proc, level)
    end
    
        
    private
  
    def check_for_asset_2( filename_s, suffix, filename_to_asset_conversion_proc, level = nil )
      assetname, origin = filename_to_asset_conversion_proc.call( filename_s, suffix, level)
      todo = !File.exists?( assetname )
      if !todo
	    @logger.debug( "Skip: Asset exists (#{ origin } -> #{ File.basename( assetname ) })" )
      end
      return assetname, todo
    end  
    def digest_over_content( file )
      @logger.debug(" digest_over_content file = #{file}.")
      Digest::MD5.hexdigest( File.read( file ) )
    end
    def digest_over_file_basename( file )
      @logger.debug(" digest_over_file_basename file = #{file}.")
      Digest::MD5.hexdigest( File.basename( file ) )
    end
    def digest_over_string( s )
      Digest::MD5.hexdigest( s )
    end
            
  end
  
  class AudioAssetfunctions < AssetFunctions
    def initialize(output_type_obj, samplerate, bps, channelcount )
      super(output_type_obj)
      @samplerate = samplerate 
      @bps = bps
      @channelcount = channelcount
    end
    def check_for_silence_asset( suffix, seconds, level = nil )
      suffix2 = seconds.to_s + '_' + @samplerate.to_s + '_' + @bps.to_s + '_' + @channelcount.to_s + suffix 
      check_for_asset_2( SILENCE_FILENAME_PREFIX, suffix2, simple_conversion_proc, level = nil )
    end
    def check_for_sequence_audio_asset (conformed_audio_list, image_sequence_length_seconds, suffix)
      set = Array.new
      conformed_audio_list.each do |e|
	set << File.basename( e )
      end
      filename = "#{ digest_over_string( set.join ) }"
      suffix2 = "_sequence_#{ image_sequence_length_seconds }#{ suffix }"
      check_for_asset_2( filename, suffix2, simple_conversion_proc, level = nil )
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
      @expanded_assetsdir = File.expand_path(@output_type_obj.assetsdir)
    end
    def check_for_black_asset( suffix, level = nil )
      check_for_asset_2( FILENAME_BLACK_FRAME, suffix, filename_to_asset_conversion_proc, nil )
    end
    private
    def filename_to_asset_conversion_proc
      Proc.new do |filename_s, suffix, level |
	# 2 images from crossfade?
	if filename_s.size == 2
	  id = filename_hash2( filename_s[0]) + '_' + filename_hash2( filename_s[1])
	  origin = [ File.basename( filename_s[ 0 ] ), File.basename( filename_s[ 1 ] ) ].join( ' X ' )
	else # not from crossfade
	  id = File.exists?( filename_s ) ? filename_hash2( filename_s) :  FILENAME_BLACK_FRAME   
	  origin = File.basename( filename_s )
	end
	assetname = File.join( @output_type_obj.assetsdir, id + "_#{ @output_type_obj.dimensions }_#{ @resize ? 'r' : 'nr' }#{ level.nil? ? '' : '_' + level.to_s }#{ @output_type_obj.asset_suffix(suffix) }" )
	assetname, origin = assetname, origin
      end
    end
    # TODO: take care: this is only a filenamehash
    # if you want an exact hash for only the image date use
    # `identify -format '%#' #{ filename }` instead
    def filename_hash( file)
      ShellCommands.sha1sum_command( file )
    end
    
    # Thanks Wolfgang
    # entry into the asset depot will trigger a relatively strong and good enough md5 digest over content
    # members of the asset depot will trigger a cheaper and good enough digest over filename (which is in part an md5 digest)
    #   + dimensions + (level unless jpeg 2000 codestream requested) + (encoder + fps if jpeg 2000 codestream is requested) + suffix
    def filename_hash2( file)
      if File.expand_path(File.dirname( file )) != @expanded_assetsdir 
        digest_over_content( file )
      else
        digest_over_file_basename( file )
      end
    end

  
  end
  
  class ThumbAssetFunctions < AssetFunctions
    def check_for_montage_asset( filename_s, suffix, level = nil )
      check_for_asset_2( filename_s, suffix, filename_to_montage_asset_conversion_proc, level)
    end
    private 
    def filename_to_montage_asset_conversion_proc
      Proc.new do |filename_s, suffix, level |
	assetname = File.join( @output_type_obj.thumbsdir, Digest::MD5.hexdigest( filename_s ) + "_#{ @output_type_obj.thumbs_dimensions }_" + MONTAGE_FILENAME_SUFFIX + suffix )
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