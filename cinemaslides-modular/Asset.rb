module Asset
  
  require 'ShellCommands'
  require 'Logger'
  
  ShellCommands = ShellCommands::ShellCommands

  
  class AssetFunctions
    def initialize(output_type_obj)
      @output_type_obj = output_type_obj
      @logger = Logger::Logger.instance
    end
    
    # asset match is based on a /conform's/ IM signature + dimensions + (level unless jpeg 2000 codestream requested) + (encoder + fps if jpeg 2000 codestream is requested) + suffix
    
    def check_for_asset( filename_s, suffix, level = nil )
      check_for_asset_2( filename_s, suffix, filename_to_asset_conversion_proc, level = nil )
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
      check_for_asset_2( 'silence_', suffix2, simple_conversion_proc, level = nil )
    end
    def check_for_sequence_audio_asset (conformed_audio_list, image_sequence_length_seconds, suffix)
      set = Array.new
      conformed_audio_list.each do |e|
	set << File.basename( e )
      end
      filename = "#{ Digest::SHA1.hexdigest( set.join ) }"
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
	hexdigest = Digest::SHA1.hexdigest( File.read( filename_s ) )
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
    private
    def filename_to_asset_conversion_proc
      Proc.new do |filename_s, suffix, level |
	# 2 images from crossfade?
	if filename_s.size == 2
	  id = filename_hash( filename_s[0]) + '_' + filename_hash( filename_s[1])
	  origin = [ File.basename( filename_s[ 0 ] ), File.basename( filename_s[ 1 ] ) ].join( ' X ' )
	else # not from crossfade
	  id = File.exists?( filename_s ) ? filename_hash( filename_s) : 'black'    
	  origin = File.basename( filename_s )
	end
	assetname = File.join( @output_type_obj.assetsdir, id + "_#{ @output_type_obj.dimensions }_#{ @resize ? 'r' : 'nr' }#{ level.nil? ? '' : '_' + level.to_s }#{ @output_type_obj.asset_suffix(suffix) }" )
	assetname, origin = assetname, origin
      end
    end
    
    def filename_hash( file)
      ShellCommands.sha1sum_command( file )
    end
  end
  
  class ThumbAssetFunctions < AssetFunctions
    private 
    def filename_to_asset_conversion_proc
      Proc.new do |filename_s, suffix, level |
	assetname = File.join( @output_type_obj.thumbsdir, Digest::MD5.hexdigest( File.exists?( filename_s) ? File.read( filename_s ) : filename_s ) + "_#{ @output_type_obj.thumbs_dimensions }_" + suffix )
	origin = File.basename( filename_s )
	assetname, origin = assetname, origin
      end
    end
  end
  

end