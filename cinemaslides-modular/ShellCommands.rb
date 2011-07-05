module ShellCommands
  require 'CinemaslidesCommon'
  
  # shell escape has to be done for strings handed over to the shell, that might
  # contain blanks or special characters or string delimiters
  class ShellCommands
    def self.image_identify_command( file )
      `identify -ping -format '%m' #{ CSTools.shell_escape( file ) } 2>/dev/null`    
    end
    def self.soxi_V0_t_command(file)
      `soxi -V0 -t #{ CSTools.shell_escape( file ) } 2>&1`
    end
    def self.soxi_V0_d_command(file)
      `soxi -V0 -d #{ CSTools.shell_escape( file ) } 2>&1`
    end
    def self.soxi_D_command( file )
      `soxi -D #{ CSTools.shell_escape( file ) }`
    end
    def self.sox_splice_command( file_list, output )
      `sox #{ file_list.collect!{|file| CSTools.shell_escape( file )  }.join(" ") } #{ CSTools.shell_escape( output ) } splice`
    end
    def self.sox_trim_command( from_audio_file, to_audio_file, duration_hms)
      `sox #{ CSTools.shell_escape( from_audio_file ) } #{ CSTools.shell_escape( to_audio_file ) } trim 0 #{ duration_hms }`
    end
    def self.sox_to_PCM24_command( audiofile, samplerate, bps, channelcount, output)
      `sox #{ CSTools.shell_escape( audiofile ) } -r #{ samplerate } -b #{ bps } -c #{ channelcount } -s -t wavpcm #{ CSTools.shell_escape( output ) } gain -n -20`  
    end
    def self.sox_silence_command( samplerate, bps, channelcount, silence_file, seconds )
      `sox -r #{ samplerate } -b #{ bps } -c #{ channelcount } -s -n #{ CSTools.shell_escape( silence_file ) } synth #{ seconds } sine 0`
    end
    def self.openssl_sha1_64( file )
      `openssl dgst -sha1 -binary #{ CSTools.shell_escape( file ) } | openssl base64`
    end
    def self.openssl_sha1_64_string( string ) 
      `echo -n '#{ string }' | openssl dgst -sha1 -binary | openssl base64`
    end
    # TODO check if correct
    def self.base64(s) 
      `echo -n #{ CSTools.shell_escape( s ) } | openssl base64 -d`
    end
    # sh does not accept named pipes created by process substitution, so we have to call bash
    # 
    def self.dc_thumbprint(cert_file)
      tmp = Tempfile.new( 'cinemaslides-' )
      `bash -c "openssl asn1parse -in #{ CSTools.shell_escape( cert_file ) } -out #{ tmp.path } -noout -strparse 4"`
      `openssl dgst -sha1 -binary #{ tmp.path } | openssl base64`.chomp
    end
    # \\\" is because of the double shell call
    # 
    def self.dc_thumbprint_string(cert)
      tmp_file = Tempfile.new( 'cinemaslides-' )
      File.open( tmp_file.path, 'w' ) { |f| f.write cert ; f.close }
      ShellCommands::dc_thumbprint( tmp_file.path )
#      ShellCommands::dc_thumbprint("<(echo -e \\\"#{ cert.gsub("\n","\\n") }\\\")")
##      ShellCommands::dc_thumbprint("<(echo -e #{ cert.gsub("\n","\\n") })")
    end
    def self.display_command( file )
      `display #{ CSTools.shell_escape( file ) }`
    end
    def self.mplayer_preview_command( file, audio, fps, output_format, mplayer_vo, gamma)
      `mplayer -really-quiet mf://#{ CSTools.shell_escape( file ) } #{ audio } -mf fps=#{ fps }:type=#{ output_format } -loop 0 #{ mplayer_vo } -vf eq2=#{ gamma } > /dev/null 2>&1`
    end
    def self.uuid_gen
      `kmuuidgen -n`
    end
    def self.rm_rf_command( dir )
      `rm -rf #{ CSTools.shell_escape( dir ) }`
    end
    def self.touch_command( file )
      `touch #{ CSTools.shell_escape( file ) } > /dev/null 2>&1`
    end
    def self.IM_convert_info_command( file )
      `convert #{ CSTools.shell_escape( file ) } -format '(%wx%h, 1:%[fx:w/h])' info:`
    end
    def self.p_IM_convert_resize_extent_color_specs( image, filename, resize, dimensions)
      `convert #{ CSTools.shell_escape( image ) } \
	-type TrueColor \
	-alpha Off \
	-gamma 0.454545454545455 \
	#{ resize ? '-resize ' + dimensions : '' } \
	-background black \
	-gravity center #{ (filename.end_with?('.jpg')) ? ' -quality 92' : '' }\
	-extent #{ dimensions } \
	-gamma 2.2 \
	-depth 8  \
	-strip \
	-sampling-factor 2x2 \
      #{ CSTools.shell_escape( filename ) }`
    end
    def self.p_IM_convert_apply_level( image, level, filename )
      # alternatives to "-fill black -colorize #{ level.abs }" would be
      # composite source -size [source's size] xc:black -blend level.abs result
      #"-modulate #{ level + 100 }"#,#{ level + 100 }" # second parameter is saturation. this one has channel clipping issues
      #"-modulate #{ level + 100 } -blur 0x#{ level }" # experiment, color starvation -> heavy banding
      #"-brightness-contrast #{ level }x#{ level }" # not in ubuntu 10.04's im 6.5.7-8, crushes off into swamp blacks
      `convert #{ CSTools.shell_escape( image ) } \
	  -type TrueColor \
	  -gamma 0.454545454545455 \
	  -fill black -colorize #{ level.abs } \
	  -gamma 2.2  #{ (filename.end_with?('.jpg')) ? ' -quality 92' : '' }\
	  #{ CSTools.shell_escape( filename ) }`
    end
    def self.p_IM_black_frame( file, dimensions )
      `convert -type TrueColor -size #{ dimensions } xc:black -depth 8 #{ CSTools.shell_escape( file ) }`
    end
    def self.smpte_dcp_IM_convert_resize_extent_color_specs( image, filename, resize, dimensions)
      `convert #{ CSTools.shell_escape( image ) } \
	-type TrueColor \
	-alpha Off \
	-gamma 0.454545454545455 \
	#{ resize ? '-resize ' + dimensions : '' } \
	-background black \
	-gravity center \
	-extent #{ dimensions } \
	-recolor '#{ CinemaslidesCommon::SRGB_TO_XYZ }' \
	-gamma 2.6 \
	-depth 12 \
	-compress none  \
	#{ CSTools.shell_escape( filename ) }`
    end
    def self.smpte_dcp_IM_convert_apply_level( image, level, filename )
      # alternatives to "-fill black -colorize #{ level.abs }" would be
      # composite source -size [source's size] xc:black -blend level.abs result
      #"-modulate #{ level + 100 }"#,#{ level + 100 }" # second parameter is saturation. this one has channel clipping issues
      #"-modulate #{ level + 100 } -blur 0x#{ level }" # experiment, color starvation -> heavy banding
      #"-brightness-contrast #{ level }x#{ level }" # not in ubuntu 10.04's im 6.5.7-8, crushes off into swamp blacks
      `convert #{ CSTools.shell_escape( image ) } \
	  -type TrueColor \
	  -gamma 0.38461538461538458 \
	  -fill black -colorize #{ level.abs } \
	  -gamma 2.6 \
	  -depth 12  \
	  -compress none \
	  #{ CSTools.shell_escape( filename ) }`
    end
    def self.smpte_dcp_IM_black_frame( file, dimensions )
      `convert -type TrueColor -size #{ dimensions } xc:black -depth 12 #{ CSTools.shell_escape( file ) }`
    end
    def self.IM_convert_thumb(single_source, thumbs_dimensions, output)
      `convert #{ single_source } \
	-type TrueColor \
	-resize #{ thumbs_dimensions } \
	-background black \
	-gravity center \
	-extent #{ thumbs_dimensions } \
	-depth 8 \
      #{ CSTools.shell_escape( output ) }`
    end
    # thumbs is an Array of filenames
    def self.IM_montage(thumbs, source_length, thumbs_dimensions, output)
      tiles_x = Math.sqrt( source_length ).ceil
      `montage #{ thumbs.collect!{|file| CSTools.shell_escape( file )  }.join( ' ' ) } \
	-mode Concatenate \
	-tile #{ tiles_x }x \
	-border 1 \
	-geometry '#{ thumbs_dimensions }+5+5>' \
	-bordercolor lightblue \
      #{ CSTools.shell_escape( output ) }`
    end
    def self.IM_composite_command( image1, level, image2, depth_parameter, compress_parameter, output)
      `composite -type TrueColor #{ (image1.end_with?('.jpg')) ? ' -quality 92' : '' } #{ CSTools.shell_escape( image1 ) } -dissolve #{ level } #{ (image2.end_with?('.jpg')) ? ' -quality 92' : '' }  #{ CSTools.shell_escape( image2 ) } #{ depth_parameter } #{ compress_parameter } #{ (output.end_with?('.jpg')) ? ' -quality 92' : '' } #{ CSTools.shell_escape( output ) } `
    end
    def self.IM_composite_rotate_command( image1, rotation, level, image2, depth_parameter, compress_parameter, output)
      `convert #{ CSTools.shell_escape( image1 ) } -background black -geometry 1920x1080!  -rotate #{ rotation } miff:- | composite -type TrueColor miff:- -dissolve #{ level } #{ CSTools.shell_escape( image2 ) } #{ depth_parameter } #{ compress_parameter } #{ CSTools.shell_escape( output ) }`
    end
    # TODO check for shell_escape
    def self.openssl_rsautl_base_64( target, path)
      `openssl rsautl -encrypt -oaep -certin -inkey #{ target } -in #{ path } | openssl base64`
    end
    def self.opendcp_j2k_command( file, output, additional_options )
      @logger = Logger::Logger.instance
      @logger.debug("OpenDcp COMMAND = opendcp_j2k -i #{ CSTools.shell_escape( file ) } -o #{ CSTools.shell_escape( output ) } -x #{ additional_options }")
      `opendcp_j2k -i #{ CSTools.shell_escape( file ) } -o #{ CSTools.shell_escape( output ) } -x #{ additional_options }`
    end
    def self.kakadu_encode_command( file, output, profile, max_bpi, max_bpc)
      `kdu_compress -i #{ CSTools.shell_escape( file ) } -o #{ CSTools.shell_escape( output ) } Sprofile=#{ profile } Creslengths=#{ max_bpi } Creslengths:C0=#{ max_bpi },#{ max_bpc } Creslengths:C1=#{ max_bpi },#{ max_bpc } Creslengths:C2=#{ max_bpi },#{ max_bpc }`
    end
    def self.image_to_j2k_command( file, output, profile )
      `image_to_j2k -#{ profile } -i #{ CSTools.shell_escape( file ) } -o #{ CSTools.shell_escape( output ) }`
    end
    def self.hostname_command
      `hostname`
    end
    def self.asdcp_test_v_i_command( mxf_file )
      `asdcp-test -v -i #{CSTools.shell_escape( mxf_file )  }`
    end
    def self.random_128_bit
      `kmrandgen -n -s 16`
    end
    # shell escape has to be done in method that calls asdcp_test_create_mxf
    def self.asdcp_test_create_mxf( args )
      asdcp_line = "asdcp-test #{ args } > /dev/null 2>&1"
      Logger::Logger.instance.debug( asdcp_line )
      `#{ asdcp_line }`
    end
    def self.sha1sum_command( file )
      `sha1sum #{ CSTools.shell_escape( file ) }`.chomp.split(" ")[0]
    end
    def self.xmlsec_command( signer_key_file, ca_cert_file, intermediate_cert_file , path)
      `xmlsec1 --sign --privkey-pem #{ CSTools.shell_escape( signer_key_file ) } --trusted-pem #{ CSTools.shell_escape( ca_cert_file ) } --trusted-pem #{ CSTools.shell_escape( intermediate_cert_file ) } #{ CSTools.shell_escape( path ) }`
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
      `xmlsec1 --sign --id-attr:Id http://www.smpte-ra.org/schemas/430-3/2006/ETM:AuthenticatedPublic --id-attr:Id http://www.smpte-ra.org/schemas/430-3/2006/ETM:AuthenticatedPrivate --privkey-pem #{ CSTools.shell_escape( signer_key_file ) } --trusted-pem #{ CSTools.shell_escape( ca_cert_file ) } --trusted-pem #{ CSTools.shell_escape( intermediate_cert_file ) } #{ CSTools.shell_escape( path ) }`
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