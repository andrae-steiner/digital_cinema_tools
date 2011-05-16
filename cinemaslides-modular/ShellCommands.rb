module ShellCommands
    
  class ShellCommands
    def self.image_identify_command( file )
      `identify -ping -format '%m' #{ file } 2>/dev/null`    
    end
    def self.soxi_V0_t_command(file)
      `soxi -V0 -t #{ file } 2>&1`
    end
    def self.soxi_V0_d_command(file)
      `soxi -V0 -d #{ file } 2>&1`
    end
    def self.soxi_D_command( file )
      `soxi -D #{ file }`
    end
    def self.sox_splice_command( *list )
      `sox #{ list.join(" ") } splice`
    end
    def self.sox_trim_command( sequence_audio_asset_tmp, sequence_audio_asset, image_sequence_length_hms)
      `sox #{ sequence_audio_asset_tmp } #{ sequence_audio_asset } trim 0 #{ image_sequence_length_hms }`
    end
    def self.sox_to_PCM24_command( audiofile, samplerate, bps, channelcount, asset)
      `sox #{ audiofile } -r #{ samplerate } -b #{ bps } -c #{ channelcount } -s -t wavpcm #{ asset } gain -n -20`  
    end
    def self.sox_silence_command( samplerate, bps, channelcount, silence_conform, seconds )
      `sox -r #{ samplerate } -b #{ bps } -c #{ channelcount } -s -n #{ silence_conform } synth #{ seconds } sine 0`
    end
    def self.IM_convert_info_command( file )
      `convert #{ file } -format '(%wx%h, 1:%[fx:w/h])' info:`
    end
    def self.openssl_sha1_64( file )
      `openssl dgst -sha1 -binary #{ file } | openssl base64`
    end
    def self.openssl_sha1_64_string( string ) 
      `echo -n '#{string}' | openssl dgst -sha1 -binary | openssl base64`
    end
    def self.base64(s) 
      `echo -n '#{s}' | openssl base64 -d`
    end
    # sh does not accept named pipes created by process substitution, so we have to call bash
    # 
    def self.dc_thumbprint(cert_file)
      tmp = Tempfile.new( 'cinemaslides-' )
      `bash -c "openssl asn1parse -in #{ cert_file } -out #{ tmp.path } -noout -strparse 4"`
      `openssl dgst -sha1 -binary #{ tmp.path } | openssl base64`.chomp
    end
    # \\\" is because of the double shell call
    # 
    def self.dc_thumbprint_string(cert)
      ShellCommands::dc_thumbprint("<(echo -e \\\"#{ cert.gsub("\n","\\n") }\\\")")
#      ShellCommands::dc_thumbprint("<(echo -e #{ cert.gsub("\n","\\n") })")
    end
    def self.display_command( file )
      `display #{ file }`
    end
    def self.mplayer_preview_command( sequence, audio, fps, output_format, mplayer_vo, gamma)
      `mplayer -really-quiet mf://#{ sequence } #{ audio } -mf fps=#{ fps }:type=#{ output_format } -loop 0 #{ mplayer_vo } -vf eq2=#{ gamma } > /dev/null 2>&1`
    end
    def self.uuid_gen
      `kmuuidgen -n`
    end
    def self.rm_rf_command( dir )
      `rm -rf #{ dir }`
    end
    def self.touch_command( file )
      `touch #{ file } > /dev/null 2>&1`
    end
    def self.p_IM_convert_resize_extent_color_specs( image, filename, resize, dimensions)
      `convert #{image} \
	-type TrueColor \
	-alpha Off \
	-gamma 0.454545454545455 \
	#{ resize ? '-resize ' + dimensions : '' } \
	-background black \
	-gravity center \
	-extent #{ dimensions } \
	-gamma 2.2 \
	-depth 8  \
	-strip \
	-sampling-factor 2x2 \
      #{ filename }`
    end
    def self.p_IM_convert_apply_level( image, level, filename )
      # alternatives to "-fill black -colorize #{ level.abs }" would be
      # composite source -size [source's size] xc:black -blend level.abs result
      #"-modulate #{ level + 100 }"#,#{ level + 100 }" # second parameter is saturation. this one has channel clipping issues
      #"-modulate #{ level + 100 } -blur 0x#{ level }" # experiment, color starvation -> heavy banding
      #"-brightness-contrast #{ level }x#{ level }" # not in ubuntu 10.04's im 6.5.7-8, crushes off into swamp blacks
      `convert #{image} \
	  -type TrueColor \
	  -gamma 0.454545454545455 \
	  -fill black -colorize #{ level.abs } \
	  -gamma 2.2 \
	  #{ filename }`
    end
    def self.p_IM_black_frame( file, dimensions )
      `convert -type TrueColor -size #{ dimensions } xc:black -depth 8 #{ file }`
    end
    def self.smpte_dcp_IM_convert_resize_extent_color_specs( image, filename, resize, dimensions)
      `convert #{image} \
	-type TrueColor \
	-alpha Off \
	-gamma 0.454545454545455 \
	#{ resize ? '-resize ' + dimensions : '' } \
	-background black \
	-gravity center \
	-extent #{ dimensions } \
	-recolor '#{ OutputType::SRGB_TO_XYZ }' \
	-gamma 2.6 \
	-depth 12 \
	-compress none  \
	#{ filename }`
    end
    def self.smpte_dcp_IM_convert_apply_level( image, level, filename )
      # alternatives to "-fill black -colorize #{ level.abs }" would be
      # composite source -size [source's size] xc:black -blend level.abs result
      #"-modulate #{ level + 100 }"#,#{ level + 100 }" # second parameter is saturation. this one has channel clipping issues
      #"-modulate #{ level + 100 } -blur 0x#{ level }" # experiment, color starvation -> heavy banding
      #"-brightness-contrast #{ level }x#{ level }" # not in ubuntu 10.04's im 6.5.7-8, crushes off into swamp blacks
      `convert #{image} \
	  -type TrueColor \
	  -gamma 0.38461538461538458 \
	  -fill black -colorize #{ level.abs } \
	  -gamma 2.6 \
	  -depth 12  \
	  -compress none \
	  #{ filename }`
    end
    def self.smpte_dcp_IM_black_frame( file, dimensions )
      `convert -type TrueColor -size #{ dimensions } xc:black -depth 12 #{ file }`
    end
    def self.hostname_command
      `hostname`
    end
    def self.asdcp_test_v_i_command( mxf )
      `asdcp-test -v -i #{ mxf }`
    end
    def self.random_128_bit
      `kmrandgen -n -s 16`
    end
    def self.asdcp_test_create_mxf( args )
      asdcp_line = "asdcp-test #{ args } > /dev/null 2>&1"
      Logger::Logger.instance.debug( asdcp_line )
      `#{ asdcp_line }`
    end
    def self.IM_convert_thumb(single_source, thumbs_dimensions, thumbasset)
      `convert #{ single_source } \
	-type TrueColor \
	-resize #{ thumbs_dimensions } \
	-background black \
	-gravity center \
	-extent #{ thumbs_dimensions } \
	-depth 8 \
      #{ thumbasset }`
    end
    def self.IM_montage(thumbs, source_length, thumbs_dimensions, thumbs_asset)
      tiles_x = Math.sqrt( source_length ).ceil
      `montage #{ thumbs } \
	-mode Concatenate \
	-tile #{ tiles_x }x \
	-border 1 \
	-geometry '#{ thumbs_dimensions }+5+5>' \
	-bordercolor lightblue \
      #{ thumbs_asset }`
    end
    def self.IM_composite_command( image1, level, image2, depth_parameter, compress_parameter, output)
      `composite -type TrueColor #{ image1 } -dissolve #{ level } #{ image2 } #{ depth_parameter } #{ compress_parameter } #{ output }`
    end
    def self.IM_composite_rotate_command( image1, rotation, level, image2, depth_parameter, compress_parameter, output)
      `convert #{image1} -background black -geometry 1920x1080!  -rotate #{ rotation } miff:- | composite -type TrueColor miff:- -dissolve #{ level } #{ image2 } #{ depth_parameter } #{ compress_parameter } #{ output }`
    end
    def self.openssl_rsautl_base_64( target, path)
      `openssl rsautl -encrypt -oaep -certin -inkey #{ target } -in #{ path } | openssl base64`
    end
    def self.opendcp_j2k_command( file, asset, additional_options )
      @logger = Logger::Logger.instance
      @logger.debug("OpenDcp COMMAND = opendcp_j2k -i #{ file } -o #{ asset } -x #{ additional_options }")
      `opendcp_j2k -i #{ file } -o #{ asset } -x #{ additional_options }`
    end
    def self.kakadu_encode_command( file, asset, profile, max_bpi, max_bpc)
      `kdu_compress -i #{ file } -o #{ asset } Sprofile=#{ profile } Creslengths=#{ max_bpi } Creslengths:C0=#{ max_bpi },#{ max_bpc } Creslengths:C1=#{ max_bpi },#{ max_bpc } Creslengths:C2=#{ max_bpi },#{ max_bpc }`
    end
    def self.image_to_j2k_command( file, asset, profile )
      `image_to_j2k -#{ profile } -i #{ file } -o #{ asset }`
    end
    def self.sha1sum_command( file )
      `sha1sum #{ file }`.chomp.split(" ")[0]
    end
    def self.xmlsec_command( signer_key_file, ca_cert_file, intermediate_cert_file , path)
      `xmlsec1 --sign --privkey-pem #{ signer_key_file } --trusted-pem #{ ca_cert_file } --trusted-pem #{ intermediate_cert_file } #{ path }`
    end
    # sh does not accept named pipes created by process substitution
    # 
    # for a solution see dc_thumbprint, dc_thumbprint_string
    def self.xmlsec_command_strings( signer_key, ca_cert, intermediate_cert , path)
      tmp_files = Array.new
      [signer_key, ca_cert, intermediate_cert].each_with_index do |key_cert, i|
	tmp_files[i] = Tempfile.new( 'cinemaslides-' )
	tmp = File.open( tmp_files[i].path, 'w' ) { |f| f.write key_cert ; f.close }
      end
      ShellCommands::xmlsec_command( tmp_files[0].path, tmp_files[1].path, tmp_files[2].path, path)
    end
    def self.xmlsec_KDM_command( signer_key_file, ca_cert_file, intermediate_cert_file , path)
      # FIXME hardcoded certificate chain size
      `xmlsec1 --sign --id-attr:Id http://www.smpte-ra.org/schemas/430-3/2006/ETM:AuthenticatedPublic --id-attr:Id http://www.smpte-ra.org/schemas/430-3/2006/ETM:AuthenticatedPrivate --privkey-pem #{ signer_key_file } --trusted-pem #{ ca_cert_file } --trusted-pem #{ intermediate_cert_file } #{ path }`
    end
    # sh does not accept named pipes created by process substitution
    # 
    # for a solution see dc_thumbprint, dc_thumbprint_string
    def self.xmlsec_KDM_command_strings( signer_key, ca_cert, intermediate_cert , path)
      # FIXME hardcoded certificate chain size
        tmp_files = Array.new
        [signer_key, ca_cert, intermediate_cert].each_with_index do |key_cert, i|
	  tmp_files[i] = Tempfile.new( 'cinemaslides-' )
	  tmp = File.open( tmp_files[i].path, 'w' ) { |f| f.write key_cert ; f.close }
	end
      ShellCommands::xmlsec_KDM_command( tmp_files[0].path, tmp_files[1].path, tmp_files[2].path, path)        
    end

  end # class

end # module