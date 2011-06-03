module AudioSequence
  
  require 'Logger'
  require 'ShellCommands'
  require 'Asset'
  require 'CinemaslidesCommon'
  ShellCommands = ShellCommands::ShellCommands
    
### Process audio (asset-audio depot is still a moving target, bugs lurking etc., as of v0.2010.09.07)
#
# user can specify -- alongside with any number of images -- any number of audio files
# a) cinemaslides makes a list which will be equally long as or longer than the calculated image sequence
#    when the total length of the specified audio files is not long enough the list-making process will start over until length is sufficient
#    (e.g. user specifies [a.wav b.wav c.wav] with 1 min total length, image sequence is 1:30 min, audio list will be [a.wav b.wav c.wav a.wav ...]
#     and will be trimmed to 1:30 min)
# b) every element of the list is then checked into the asset depot
# c) the elements are spliced together (result is checked into asset depot)
# d) the result is trimmed to the exact length of the image sequence
# e) the result is padded with silence to accomodate for black leader/tail

  class AudioSequence
    def initialize(source, image_sequence, output_type_obj, fps, audio_samplerate, audio_bps, 
                   black_leader, black_tail)
      @logger = Logger::Logger.instance
      @source_audio = source
      @image_sequence = image_sequence
      @output_type_obj = output_type_obj
      @fps = fps
      @audio_samplerate = audio_samplerate
      @audio_bps = audio_bps
      @black_leader = black_leader
      @black_tail = black_tail
      @audio_channel_count = 2   # FIXME channelcount
      @asset_functions = Asset::AudioAssetfunctions.new( output_type_obj, audio_samplerate, audio_bps, @audio_channel_count )
    end
    
    def audio_source_to_pcm
      @logger.info( 'Conform audio ...' )
      
      audio_list = Array.new
      audio_list_total_length = 0.0
      conformed_audio_list = Array.new
      source_audio_index = 0
      
      image_sequence_length_seconds = @image_sequence.n_image_sequence_frames / @fps
      @logger.debug("AUDIO: image_sequence.n_image_sequence_frames = #{ @image_sequence.n_image_sequence_frames }")
      
      image_sequence_length_hms = hms_from_seconds( image_sequence_length_seconds ) #  needed for sox/trim
      
      # a) make a list of audiofiles with sufficient total length (read 'at least as long as image sequence')
      while audio_list_total_length < image_sequence_length_seconds
	audio_list << @source_audio[ source_audio_index ]
	audio_list_total_length += ShellCommands.soxi_D_command( @source_audio[ source_audio_index ] ).chomp.to_f
	if source_audio_index == @source_audio.size - 1
	  source_audio_index = 0 # start over
	else
	  source_audio_index += 1
	end
      end
      
      # b) conform the required audiofiles
      audio_list.each do |audiofile|
	audio_asset = conform_audio( audiofile) # FIXME channelcount
	conformed_audio_list << audio_asset
      end
      
      # match for sequence_audio_asset is based on image sequence length and sha1 digest of conformed_audio_list's elements (assets) joined into 1 string

      # c) splice d) trim
      
      conform_sequence_audio(conformed_audio_list,  "_" + CinemaslidesCommon::FILE_SUFFIX_PCM )
      
      # e) pad with silence for black leader/tail
      audio_leader = ( @black_leader > 0 ? conform_silence( @black_leader) : '' )
      audio_tail = ( @black_tail > 0 ? conform_silence( @black_tail ) : '' )
      if @black_leader + @black_tail > 0
	@logger.debug( 'Pad audio with leader/tail silence' )
	@final_audio = File.join( @output_type_obj.assetsdir_audio, 'padded_' + File.basename( @sequence_audio_asset ) )
	ShellCommands.sox_splice_command(audio_leader, @sequence_audio_asset, audio_tail, @final_audio )
      else
	@final_audio = @sequence_audio_asset
      end
      
      @logger.info( '... Conform audio done' )
      return @final_audio
    end
    
    private 
    
    def conform_sequence_audio (conformed_audio_list, suffix)
      image_sequence_length_seconds = @image_sequence.n_image_sequence_frames / @fps
      image_sequence_length_hms = hms_from_seconds( image_sequence_length_seconds ) #  needed for sox/trim
      @sequence_audio_asset, todo = @asset_functions.check_for_sequence_audio_asset( conformed_audio_list, image_sequence_length_seconds, "_" + CinemaslidesCommon::FILE_SUFFIX_PCM )
      if todo
	sequence_audio_asset_tmp = File.join( @output_type_obj.assetsdir_audio, 'tmp-' + File.basename( @sequence_audio_asset ) )
	ShellCommands.sox_splice_command( conformed_audio_list.join( ' ' ), sequence_audio_asset_tmp )
	ShellCommands.sox_trim_command(sequence_audio_asset_tmp, @sequence_audio_asset, image_sequence_length_hms)
	File.delete( sequence_audio_asset_tmp )
      end
    end
        
    def conform_audio( audiofile )
      @logger.info( "Conform audio: #{ audiofile }" )
      asset, todo = @asset_functions.check_for_asset(audiofile, "_" + CinemaslidesCommon::FILE_SUFFIX_PCM )
      # asset, todo = check_for_audio_asset( audiofile, samplerate, bps, channelcount )
      if todo
	# also  normalise to -20 dB FS (SMPTE 428-2-2006)
	ShellCommands.sox_to_PCM24_command( audiofile, @audio_samplerate, @audio_bps, @audio_channel_count, asset)
      end
      return asset
    end

    def conform_silence( seconds)
      silence_conform, todo = @asset_functions.check_for_silence_asset( CinemaslidesCommon::FILE_SUFFIX_PCM, seconds, level = nil )
      if todo
	# alternatively, use asdcplib's blackwave (blackwave -d <frame_count> output)
	ShellCommands.sox_silence_command(@audio_samplerate, @audio_bps, @audio_channel_count, silence_conform, seconds)
      end
      return silence_conform
    end
    
  end # class AusioSequence
  
end  # module AudioUtils