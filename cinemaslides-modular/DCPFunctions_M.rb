module DCPFunctions_M

  require 'Logger'
  require 'Encoder'
  require 'ShellCommands'
  require 'OptParser'
  require 'ImageSequence'
  require 'MXF'
  require 'CinemaslidesCommon'
  
  ShellCommands = ShellCommands::ShellCommands
  
  
  class DCPGraphicsFormatFunctions
    attr_reader :dimensions
    def initialize
      @logger = Logger::Logger.instance
      @imagecount = 0
      @imagecount_mutex = Mutex.new
    end
    def inc_imagecount
      @imagecount_mutex.synchronize do
	@imagecount += 1
      end
    end
    def get_imagecount
      @imagecount_mutex.synchronize do
      @imagecount
      end
    end
    def convert_to_dcp_image_format (image_sequence, image_sequence_conformdir, output_type, dcp_image_sequence_name )
      raise NotImplementedError, "Do not instanciate this abstract class: #{self.class}"    
    end
  end
  
  
  class MPEGDCPGraphicsFormatFunctions < DCPGraphicsFormatFunctions
    
    def initialize
      super
      @dimensions = Hash.new
      @dimensions[CinemaslidesCommon::ASPECT_CHOICE_FLAT]      = [960, 519] # 1.85
      @dimensions[CinemaslidesCommon::ASPECT_CHOICE_SCOPE]     = [960, 402] # 2.38694638694639
      @dimensions[CinemaslidesCommon::ASPECT_CHOICE_HD]        = [960, 540] # 1.77777777777778
      @dimensions[CinemaslidesCommon::ASPECT_CONTAINER] = [960, 540]
    end
    
    def convert_to_dcp_image_format( image_sequence, image_sequence_conformdir, output_type, dcp_image_sequence_name )
       convert_to_dcp_image_format_single_thread( image_sequence, image_sequence_conformdir, output_type,dcp_image_sequence_name )
    end
    def convert_to_dcp_image_format_single_thread( image_sequence, image_sequence_conformdir, output_type, dcp_image_sequence_name )
      x,y = @dimensions[ CinemaslidesCommon::ASPECT_CONTAINER ].collect{|x| x * output_type.size.split( '' ).first.to_i}
      
      # `ffmpeg -f image2 -r #{output_type.fps} -i #{File.join(image_sequence_conformdir, CinemaslidesCommon::FILE_SEQUENCE_FORMAT+'.jpg')} -vcodec mpeg2video -pix_fmt yuv420p -s #{x}x#{y} -qscale 1 -qmin 1 -intra -r #{output_type.fps} -an #{dcp_image_sequence_name}`
      
      `ffmpeg -f image2 -r #{output_type.fps} -i #{File.join(image_sequence_conformdir, CinemaslidesCommon::FILE_SEQUENCE_FORMAT+'.jpg')} -vcodec mpeg2video -pix_fmt yuv420p -s #{x}x#{y}  -b 40000k -intra -r #{output_type.fps} -an #{dcp_image_sequence_name}`
      
    end
    
    def dcp_image_sequence_basename
      "video.#{dcp_image_sequence_suffix}"
    end
    def dcp_image_sequence_suffix
      "m2v"
    end
    def asset_suffix(suffix, options)
      "_." + suffix
    end
    
    def convert_resize_extent_color_specs( image, filename, resize, dimensions )
      image_ending = image.gsub(/.*\./, "")
      filename_ending = filename.gsub(/.*\./, "")
      identify1 = `identify -ping #{CSTools.shell_escape( image )}`.split(" ")
      @logger.debug( "image_ending = #{image_ending}, filename_ending = #{filename_ending}" )
      @logger.debug( "identify1[2] = #{identify1[2]}, dimensions = #{dimensions}" )
      ShellCommands.p_IM_convert_resize_extent_color_specs( image, filename, resize, dimensions)
    end
    def convert_apply_level( image, level, filename )
      ShellCommands.p_IM_convert_apply_level( image, level, filename)
    end  
    def create_blackframe (file, dimensions)
       ShellCommands.p_IM_black_frame( file, dimensions )
    end
    
    def convert_to_dcp_image_format( image_sequence, image_sequence_conformdir, output_type,  dcp_image_sequence_name )
      @dcp_graphics_format_functions.convert_to_dcp_image_format( image_sequence, image_sequence_conformdir, output_type,  dcp_image_sequence_name )
    end

  end
  
  
  class JPEG2000DCPGraphicsFormatFunctions < DCPGraphicsFormatFunctions

    def initialize
      super
      @dimensions = Hash.new
      @dimensions[CinemaslidesCommon::ASPECT_CHOICE_FLAT]      = [ 999, 540] # 1.85
      @dimensions[CinemaslidesCommon::ASPECT_CHOICE_SCOPE]     = [1024, 429] # 2.38694638694639
      @dimensions[CinemaslidesCommon::ASPECT_CHOICE_HD]        = [ 960, 540] # 1.77777777777778
      @dimensions[CinemaslidesCommon::ASPECT_CONTAINER] = [1024, 540]
    end

    def convert_to_dcp_image_format( image_sequence, image_sequence_conformdir, output_type,  dcp_image_sequence_name )
      Dir.mkdir( dcp_image_sequence_name )
      ## JPEG 2000 encoding
      @logger.info( "Encode to JPEG 2000" )
      filemask = File.join( image_sequence_conformdir, "*.#{ image_sequence.output_format }" )
      files = Dir.glob( filemask ).sort
            
      threads = CinemaslidesCommon::process_elements_multithreaded( files ){|i, indices|
            start_index, end_index = indices[i]
	    @logger.debug("START ENCODING THREAD")
	    convert_to_dcp_image_format_2( files.size(), image_sequence, image_sequence_conformdir, files[start_index..end_index], output_type, dcp_image_sequence_name )
      }
      
    end # def convert_to_dcp_image_format (image_sequence, image_sequence_conformdir, output_type,  dcp_image_sequence_name)
                                    
    def convert_to_dcp_image_format_2( n_total_images, image_sequence, image_sequence_conformdir, files, output_type, dcp_image_sequence_name )
	
      previous_asset = ""
      
      encoder = Encoder.const_get(encoder_classnames[output_type.jpeg2000_codec]).new(
	size = output_type.size,
	stereo = ( output_type.dcp_wrap_stereoscopic or output_type.three_D ),
	fps = image_sequence.fps)
      
      files.each do |file|
	 inc_imagecount
	# Wolfgang Woehl ad57b2f7d05f4a649e98 
	asset_link = File.join( dcp_image_sequence_name, File.basename( file ).gsub( /.#{CinemaslidesCommon::SMPTE_INTERMEDIATE_FILE_SUFFIX}$/, '.' + dcp_image_sequence_suffix )  )
	
#	if File.dirname( File.readlink( file ) ) == image_sequence_conformdir 
# 	1st file is always a link to the asset depot
# 	problematic also because it should be
	if ( File.dirname( File.readlink( file ) ) == File.expand_path(image_sequence_conformdir) ) and ( !previous_asset.eql?( "" ) )	
	  @logger.debug( "link previous_asset = #{ previous_asset }, asset_link = #{ asset_link }" )
	  File.symlink( File.expand_path(previous_asset), asset_link ) 
	  @logger.cr( "Skip (Full level): #{ File.basename( file ) } (#{ get_imagecount } of #{ n_total_images })" )
	  @logger.debug( "Skip (Full level): #{ File.basename( file ) } (#{ get_imagecount } of #{ n_total_images })" )
	else
	  
	  # helps to speed up the check_for_asset calls
	  # increases the chances that digest_over_file_basename is called in Module Asset
	  # instead of digest_over_content
	  file = CSTools.dereference_links( file )
	  
	  # possible "Skip" message only with debug verbosity
	  asset = image_sequence.asset_functions.create_asset( file, dcp_image_sequence_suffix, level = nil ) {|asset|
	    @logger.cr( "#{ output_type.jpeg2000_codec }: #{ File.basename( file ) } (#{ get_imagecount } of #{n_total_images })" )
	    @logger.debug( "#{ output_type.jpeg2000_codec }: #{ File.basename( file ) } (#{ get_imagecount } of #{ n_total_images })" )
	    @logger.debug("@options.jpeg2000_codec = #{ output_type.jpeg2000_codec }")
	    @logger.debug("Encode  >>#{file}<< to >>#{asset}<<. ");
	    encoder.encode( file, asset )
	  }
	  previous_asset = asset
	  
	  File.symlink( File.expand_path(asset),  asset_link )
	end
      end
    end # convert_to_dcp_image_format_2( n_total_images, image_sequence, image_sequence_conformdir, files, output_type, dcp_image_sequence_name )
    
    def dcp_image_sequence_basename
      dcp_image_sequence_suffix
    end
    def dcp_image_sequence_suffix
      'j2c'
    end
    def asset_suffix(suffix, options)
      fps_suffix = (options.dcp_wrap_stereoscopic or options.three_D) ? '48' : options.fps.floor.to_s 
      dcp_output_type_suffix = suffix == dcp_image_sequence_suffix ? '_' + encoder_ids[options.jpeg2000_codec] + '_' + fps_suffix : ''
      dcp_output_type_suffix + "_." + suffix
    end
  
    def convert_resize_extent_color_specs( image, filename, resize, dimensions )
      ShellCommands.smpte_dcp_IM_convert_resize_extent_color_specs( image, filename, resize, dimensions)
    end
    def convert_apply_level( image, level, filename )
      ShellCommands.smpte_dcp_IM_convert_apply_level( image, level, filename)
    end  
    def create_blackframe (file, dimensions)
      ShellCommands.smpte_dcp_IM_black_frame( file, dimensions )
    end                           

    
  end
	
  
  class DCPFunctions
    attr_reader :dimensions
    def initialize( dcp_graphics_format_functions_classname )
      @logger = Logger::Logger.instance
      @dcp_graphics_format_functions = DCPFunctions_M.const_get(dcp_graphics_format_functions_classname).new
      @dimensions = @dcp_graphics_format_functions.dimensions
    end
    def cpl_ns
      "None"
    end
    def pkl_ns
      "None"
    end
    def am_ns
      "None"
    end
    def cpl_3d_ns
      "None"
    end
    def ds_dsig
      "http://www.w3.org/2000/09/xmldsig#"
    end
    def ds_cma
      "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"
    end
    def ds_dma
      "http://www.w3.org/2000/09/xmldsig#sha1"
    end
    def ds_sma
      "None"
    end
    def ds_tma
      "http://www.w3.org/2000/09/xmldsig#enveloped-signature"
    end
    def rating_agencey
      "None"
    end
    
    def convert_resize_extent_color_specs( image, filename, resize, dimensions )
      @dcp_graphics_format_functions.convert_resize_extent_color_specs( image, filename, resize, dimensions )
    end
    def convert_apply_level( image, level, filename )
      @dcp_graphics_format_functions.convert_apply_level( image, level, filename )
    end  
    def create_blackframe( file, dimensions )
      @dcp_graphics_format_functions.create_blackframe( file, dimensions )
    end                                   
    
    def convert_to_dcp_image_format( image_sequence, image_sequence_conformdir, output_type,  dcp_image_sequence_name )
      @dcp_graphics_format_functions.convert_to_dcp_image_format( image_sequence, image_sequence_conformdir, output_type,  dcp_image_sequence_name )
    end

    def dcp_image_sequence_basename
      @dcp_graphics_format_functions.dcp_image_sequence_basename
    end
    def dcp_image_sequence_suffix
      @dcp_graphics_format_functions.dcp_image_sequence_suffix
    end
    def asset_suffix(suffix, options)
      @dcp_graphics_format_functions.asset_suffix(suffix, options)
    end

    private 
    
  end # class DCPFunctions
  
  
  class MXFInterOpDCPFunctions < DCPFunctions
    def initialize( dcp_graphics_format_functions_classname = dcp_graphics_format_functions_classnames[ CinemaslidesCommon::MPEG_GRAPHICS_FORMAT ] )
      super( dcp_graphics_format_functions_classname )
    end
    def cpl_ns
      "http://www.digicine.com/PROTO-ASDCP-CPL-20040511#"
    end
    def pkl_ns
      "http://www.digicine.com/PROTO-ASDCP-PKL-20040311#"
    end
    def am_ns
      "http://www.digicine.com/PROTO-ASDCP-AM-20040311#"
    end
    def cpl_3d_ns
      "http://www.digicine.com/schemas/437-Y/2007/Main-Stereo-Picture-CPL"
    end
    def ds_sma
      "http://www.w3.org/2000/09/xmldsig#rsa-sha1"
    end
    def rating_agencey
      "http://www.mpaa.org/2003-ratings"
    end
    def am_file_name( dir )
      File.join( dir, 'ASSETMAP' )
    end
    def mxf_UL_value_option
      " "
    end
    def dcp_kind
      'mxf interop'
    end
    def content_version_fragment(content_version_id, content_version_label, xml )
      # nothing
    end
    def get_dcp_editrate(asset_meta)
       asset_meta[ CinemaslidesCommon::MXF_KEYS_SAMPLE_RATE ].to_s.gsub( '/', ' ' )
    end
    def get_screen_aspect_ratio(dimension)      
      x, y = dimension.split( 'x' )
      (x.to_f / y.to_f).to_s[0..3]
    end
    def audio_mimetype
      "application/x-smpte-mxf;asdcpKind=Sound"
    end
    def video_mimetype
       "application/x-smpte-mxf;asdcpKind=Picture"
    end
    def subtitle_mimetype
      "text/xml;asdcpKind=Subtitle"
    end
    def cpl_mimetype
      "text/xml;asdcpKind=CPL"
    end
    def font_mimetype
      "application/ttf"
    end
    
  end # class MXFInterOpDCPFunctions < DCPFunctions
  
                                
  class SMPTEDCPFunctions < DCPFunctions
    def initialize( dcp_graphics_format_functions_classname = dcp_graphics_format_functions_classnames[ CinemaslidesCommon::JPEG2000_GRAPHICS_FORMAT ] )
      super( dcp_graphics_format_functions_classname )
    end
    def cpl_ns
      "http://www.smpte-ra.org/schemas/429-7/2006/CPL"
    end
    def pkl_ns
      "http://www.smpte-ra.org/schemas/429-8/2007/PKL"
    end
    def am_ns
      "http://www.smpte-ra.org/schemas/429-9/2007/AM"
    end
    def cpl_3d_ns
      "http://www.smpte-ra.org/schemas/429-10/2008/Main-Stereo-Picture-CPL"
    end
    def ds_sma
      "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
    end
    def rating_agency
      "http://rcq.qc.ca/2003-ratings"
    end
    def am_file_name( dir )
      File.join( dir, 'ASSETMAP.xml' )
    end
    def mxf_UL_value_option
      " -L "
    end
    def dcp_kind
      'smpte'
    end
    
    def content_version_fragment(content_version_id, content_version_label, xml )
      xml.ContentVersion_ {
	xml.Id_ "urn:uri:#{ content_version_id }"
	xml.LabelText_ content_version_label
      } # ContentVersion
    end
    def get_dcp_editrate(asset_meta)
       asset_meta[ CinemaslidesCommon::MXF_KEYS_EDIT_RATE ].to_s.gsub( '/', ' ' )
    end
    
    def get_screen_aspect_ratio(dimension)
      dimension.gsub( 'x', ' ' )
    end
    
    def audio_mimetype
      "application/mxf"
    end
    def video_mimetype
      "application/mxf"
    end
    def subtitle_mimetype
      "text/xml"
    end
    def cpl_mimetype
      "text/xml"
    end
    def font_mimetype
      "application/x-font-ttf"
    end
      
    private 
    
  end # class SMPTEDCPFunctions < DCPFunctions

end

