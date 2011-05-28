module DCP

  require 'MXF'
  require 'ShellCommands'
  require 'DCSignature'
  require 'Logger'
  
  
  ShellCommands = ShellCommands::ShellCommands
  MAIN_PICTURE_ASSET_TYPE ='MainPicture'
  MAIN_STEREOSCOPIC_PICTURE_ASSET_TYPE = 'MainStereoscopicPicture'
  MAIN_SOUND_ASSET_TYPE = 'MainSound'
  MAIN_SUBTITLE_ASSET_TYPE = 'MainSubtitle'
  CPL_ASSET_TYPES = [ MAIN_PICTURE_ASSET_TYPE, MAIN_STEREOSCOPIC_PICTURE_ASSET_TYPE, MAIN_SOUND_ASSET_TYPE, MAIN_SUBTITLE_ASSET_TYPE ]
  MIMETYPE_MXF = "application/mxf"
  MIMETYPE_XML = "text/xml"
  MIMETYPE_TTF = "application/x-font-ttf"
    
  class DCPCommonInfo
    attr_reader :issuer, :creator, :annotation, :sign
    def initialize(issuer, creator, annotation, sign)
      @issuer = issuer
      @creator = creator
      @annotation = annotation
      @sign = sign
    end # def
  end # class
  
  class CPLInfo
    attr_reader :uuid, :cpl_xml
    def initialize (uuid, cpl_xml)
      @uuid = uuid
      @cpl_xml = cpl_xml
    end # def
  end # class
  
  class DCPAsset
    attr_reader   :asset  # is a  filename, the file is not necessarily written yet
    attr_accessor :id     # is an uuid
    attr_accessor :mimetype, :asset_hash, :packinglist, :size
    def initialize (asset)
      @asset = asset
      @packinglist = FALSE
      @logger = Logger::Logger.instance
    end # def
    def self.create_asset(asset, id, mimetype, asset_hash, size, packinglist)
      asset = DCPAsset.new( asset )
      asset.id = id
      asset.mimetype = mimetype
      asset.asset_hash = asset_hash
      asset.size = size
      asset.packinglist = packinglist
      return asset
    end
  end # class
  
  # class for all assets listed in a packing list
  # Beware: dont create a DCPPKLAsset object for a packing list
  # This class is for Assets that go into a packing list
  # and not for packing lists themselves
  class DCPPKLAsset < DCPAsset
    def self.create_asset(asset, id, mimetype, asset_hash, size)
      asset = DCPPKLAsset.new( asset )
      asset.id = id
      asset.mimetype = mimetype
      asset.asset_hash = asset_hash
      asset.size = size
      return asset
    end
  end
  
  class DCPSubtitleAsset < DCPPKLAsset
    attr_reader :edit_rate, :entry_point, :duration, :intrinsic_duration
    def initialize( asset, dcp_functions, edit_rate = 0, intrinsic_duration = 0, entry_point = 0, duration = 0)
      super( asset )
      @id = get_subtitle_id(asset) #
      @mimetype = dcp_functions.subtitle_mimetype
      @size = File.size(asset)
      @edit_rate = edit_rate
      @intrinsic_duration = intrinsic_duration
      @entry_point = entry_point
      @duration = duration
      @asset_hash = asdcp_digest( asset ) if !asset.nil?
    end # def 
    
    private 
    
    def get_subtitle_id(asset)
      xml = Nokogiri::XML(  File.open( asset )  )
      id1 = xml.xpath( '//DCSubtitle/SubtitleID' ).text.gsub( ' ', '' )
      if id1.nil?
	id1 = xml.xpath( '//xmlns:SubtitleReel/xmlns:Id' ).text.gsub( ' ', '' )
      end # if
      @logger.debug("Subtitle Id = #{ id1 }.")
      id1
    end # def 
    
  end # class
  
  class DCPMXFAsset < DCPPKLAsset
    attr_reader :intrinsic_duration, :key_id, :encrypted, :stereoscopic
    attr_accessor :entry_point, :duration
    def initialize( asset )
      super(asset)
      @asset_meta = MXF::MXF_Metadata.new( asset ).hash
      @id =  @asset_meta[ MXF::MXF_KEYS_ASSETUUID ]
      @size = File.size(asset)
      @intrinsic_duration = @asset_meta[ MXF::MXF_KEYS_CONTAINER_DURATION ]
      @entry_point = 0
      @duration = @asset_meta[ MXF::MXF_KEYS_CONTAINER_DURATION ]
      @stereoscopic =  @asset_meta.has_key?( MXF::MXF_KEYS_STEREOSCOPIC )
      @asset_hash = asdcp_digest( asset )
      if @asset_meta.has_key?( MXF::MXF_KEYS_CRYPTOGRAPHIC_KEY_ID )
	@key_id = @asset_meta[ MXF::MXF_KEYS_CRYPTOGRAPHIC_KEY_ID ]
	@encrypted = TRUE
      else
	@encrypted = FALSE
      end # if 
    end # def 
  end # class
  
  class DCPMXFAudioAsset < DCPMXFAsset
    attr_reader :edit_rate
    def initialize( asset, dcp_functions )
      super(asset)
      @edit_rate =  @asset_meta[ MXF::MXF_KEYS_EDIT_RATE ].to_s.gsub( '/', ' ' )
      @mimetype = dcp_functions.audio_mimetype
    end # def 
  end # class
  
  class DCPMXFImageAsset < DCPMXFAsset
    attr_reader :edit_rate, :frame_rate, :screen_aspect_ratio
    def initialize( asset, dcp_functions, dimensions )
      super( asset )
      @edit_rate =  @asset_meta[ MXF::MXF_KEYS_SAMPLE_RATE ].to_s.gsub( '/', ' ' )
      @frame_rate = @asset_meta[ MXF::MXF_KEYS_SAMPLE_RATE ].to_s.gsub( '/', ' ' ) # FIXME SampleRate?
      # get screen_aspect_ratio not from MXF metadata, because asdcp-lib delivers
      # "wrong" values for mpeg2
      @screen_aspect_ratio =  dcp_functions.get_screen_aspect_ratio(dimensions)
      @mimetype = dcp_functions.video_mimetype
    end # def
  end # class
            
  class DCPReel
    attr_reader :image_mxf, :audio_mxf, :subtitle_xml, :image_asset, :audio_asset, :subtitle_asset
    def initialize( image_asset, audio_asset, subtitle_asset = nil )
      @image_asset = image_asset
      @audio_asset = audio_asset
      @subtitle_asset = subtitle_asset
      @audio_mxf = audio_asset.nil? ? nil: audio_asset.asset
      @image_mxf = image_asset.asset
      @subtitle_xml = subtitle_asset.nil? ? nil : subtitle_asset.asset
    end # def 
    def assets_to_a
      a = Array.new
      a << @image_asset
      a << @audio_asset if !@audio_asset.nil?
      a << @subtitle_asset if !@subtitle_asset.nil?
      return a
    end # def 
  end # class
      
  
  class DCP
    
  # assume, that the image and audiomxfs are already in the dcpdir
    
    def initialize(dcpdir, issuer, creator, annotation, sign, signature_context, dcp_functions)
      @dcp_common_info = DCPCommonInfo.new(issuer, creator, annotation, sign)
      @dcpdir = dcpdir
      @logger = Logger::Logger.instance
      @signature_context = signature_context
      @dcp_functions = dcp_functions
      @cpls = Array.new
      @packing_list = Array.new  # all the elements that go into a packing list
    end # def 
    
    # Add a font needed for subtitles to a DCP
    def add_font(font_filename, mimetype)
      font_filename2 = File.join( @dcpdir, File.basename(font_filename) )
      File.copy(font_filename, font_filename2)
      @packing_list << DCPPKLAsset.create_asset( 
	font_filename2,
	ShellCommands.uuid_gen,
	mimetype,
	asdcp_digest( font_filename2 ),
	File.size(font_filename2))
    end
    
    # Add a CPL to DCP
    def add_cpl( dcp_reels, content_title, content_kind, rating_list )      
      cpl_uuid = ShellCommands.uuid_gen # FIXME
      @logger.debug("add_cpl: cpl_uuid = #{ cpl_uuid }")
      content_version_id = cpl_uuid + '_' + DateTime.now.to_s,
      @logger.debug("add_cpl: content_version_id = #{ content_version_id }")
      content_version_label = content_version_id
      cpl = CPL_GENERIC.new( cpl_uuid, dcp_reels, @dcp_common_info, content_title, content_kind, content_version_id, content_version_label, rating_list,  @dcp_functions)
      if @dcp_common_info.sign
	cpl_new = DCSignature::DCSignature.new( cpl.xml,  @signature_context.signer_key, @signature_context.certchain_objs )
	cpl = cpl_new
      end # if
      @cpls << CPLInfo.new(cpl_uuid, cpl.xml)
                   
      # add assets of this dcp and the dcp itsself to the packing list
      dcp_reels.each do |reel| @packing_list << reel.assets_to_a end
      @packing_list << DCPPKLAsset.create_asset( 
	DCP::cpl_file( @dcpdir, cpl_uuid ),
	cpl_uuid, 
	MIMETYPE_XML,
	asdcp_digest_string( cpl.xml ), 
	cpl.xml.length )
    end # def 
    
    # Write a version file DCP.
    #
    # This method is called after one or more calls to add_cpl/add_font
    #
    # ov_dcp_asset_list ist the assetlist of the DCP to which this is the  version file DCP
    def write_vf_dcp (ov_dcp_asset_list)
      @cpls.each do |cpl|
	 @logger.info( 'Write CPL' )
	 @logger.debug( "CPL UUID:       #{ cpl.uuid }" )
         cpl_file = DCP::cpl_file( @dcpdir, cpl.uuid )
	 File.open( cpl_file, 'w' ) { |f| f.write( cpl.cpl_xml ) }
      end # each 
      create_and_write_pkl
      create_am
      # Write Assetmap
      @logger.info( 'Write ASSETMAP' )
      File.open( @am_file, 'w' ) { |f| f.write( @am.merge(ov_dcp_asset_list).xml ) }
    end # def 
    
    # Write a original version DCP.
    #
    # This method is called after one or more calls to add_cpl/add_font
    def write_ov_dcp
      @cpls.each do |cpl|
	 @logger.info( 'Write CPL' )
	 @logger.debug( "CPL UUID:       #{ cpl.uuid }" )
         cpl_file = DCP::cpl_file( @dcpdir, cpl.uuid )
	 File.open( cpl_file, 'w' ) { |f| f.write( cpl.cpl_xml ) }
      end # each 
      create_and_write_pkl
      create_am
      # Write Assetmap
      @logger.info( 'Write ASSETMAP' )
      File.open( @am_file, 'w' ) { |f| f.write( @am.xml ) }
    end # def
    
    def self.cpl_file( dir, name )
      File.join( dir, 'cpl_' + name + '_.xml' )
    end
    def self.pkl_file( dir, name )
      File.join( dir, 'pkl_' + name + '_.xml' )
    end
    def self.st_file( dir, name )
      File.join( dir, 'st_' + name + '_.xml' )
    end
    
    private       
    
    # I do not join more PKLs to one, because on ROPA there is no problem, if there are multiple PKLs.
    #
    # The difference is when you backup a cpl from the server to an external disk:
    # The principle is that, everything on the PKL that contains this CPL is backed up.
    # So if I have one PKL with several CPLs and related MXFs and subtitles, and backup one CPL of these,
    # the other CPLs and files of these other CPLs are backed up as well.      
    # If I have one PKL per CPL, only this one CPL and the corresponding MXFs and subtitles are backed up.
    # The same is with ingesting.
    #
    # I prefer the second solution: one PKL per CPL, because backup and ingesting times are shorter and you do
    # not have to deal with files, you do not need or do not want.  
    def create_and_write_pkl
      # create PackingList
      @logger.info( 'Create PKL ...' )
      @pkl_assets = Array.new
            
      # FIXME  also the fonts used in the subtitles have to go into the asset and packing list
      # TODO  check: I think this is already done
      
      
      # Feed the DCP_Assets of the cpls created plus the cpl into pkl_assets.
      @pkl_assets << @packing_list
      pkl_uuid = ShellCommands.uuid_gen
      @logger.debug( "PKL UUID:       #{ pkl_uuid }" )
      @pkl_file = DCP::pkl_file( @dcpdir, pkl_uuid )
      
      pkl = PKL_GENERIC.new(
	pkl_uuid,
	@dcp_common_info,
	@pkl_assets.flatten,
	@dcp_functions
      )
      if @dcp_common_info.sign
	pkl = DCSignature::DCSignature.new( pkl.xml,   @signature_context.signer_key, @signature_context.certchain_objs )
      end # if
      
      @pkl_dcp_asset = DCPAsset.create_asset( 
	DCP::pkl_file( @dcpdir, pkl_uuid ),
	pkl_uuid, 
	MIMETYPE_XML, 
	asdcp_digest_string( pkl.xml ), 
	pkl.xml.length, 
	packinglist = TRUE )

      # Write PackingList
      @logger.info( 'Write PKL ...' )
      File.open( @pkl_file, 'w' ) { |f| f.write( pkl.xml ) }
    end
    
    def create_am
      # create Assetmap
      @logger.info( 'Create ASSETMAP' )
      am_assets = Array.new
      
      am_assets << @packing_list  << @pkl_dcp_asset
           
      am_uuid = ShellCommands.uuid_gen
      @logger.debug( "AM UUID:        #{ am_uuid }" )
      @am_file = @dcp_functions.am_file_name( @dcpdir )
      @am = AM_GENERIC.new(
	am_uuid,
	@dcp_common_info,
	am_assets.flatten,
	@dcp_functions
      )
      if File.exists?( @am_file)
	@am.merge(@am_file)
      end
    end

  end # class
  
  # assets here are objects of type DCPAsset
  class PKL_GENERIC
    def initialize( pkl_uuid, dcp_common_info, assets, dcp_functions )
      @logger = Logger::Logger.instance
      @dcp_functions = dcp_functions
      issue_date = DateTime.now.to_s
      asset_hashes = Hash.new
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
 	xml.PackingList_( :xmlns => @dcp_functions.pkl_ns, 'xmlns:dsig' =>  @dcp_functions.ds_dsig ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } #{@dcp_functions.dcp_kind} pkl -->"
	  xml.Id_ "urn:uuid:#{ pkl_uuid }"
	  xml.AnnotationText_ dcp_common_info.annotation
	  xml.IssueDate_ issue_date
	  xml.Issuer_ dcp_common_info.issuer
	  xml.Creator_ dcp_common_info.creator
	  xml.AssetList_ {
	    assets.each do |asset|
	      xml.Asset_ {
		xml.Id_ "urn:uuid:#{ asset.id }"
		# optional: AnnotationText per asset
	        xml.Hash_ asset.asset_hash
		xml.Size_ asset.size
		xml.Type_ asset.mimetype
		xml.OriginalFileName_ File.basename( asset.asset )
	      } # Asset
	    end # assets.each
	  } # AssetList
	} # PackingList
      end # @builder
    end # initialize
    
    def xml
      return @builder.to_xml( :indent => 2 )
    end # def 
    
  end # PKL_GENERIC
  
  class DCSubtitleLine
    attr_reader :valign, :halign, :hpos, :vpos, :text
    def initialize(valign, halign, hpos, vpos, text)
      @valign = valign
      @halign = halign
      @hpos = hpos
      @vpos = vpos
      @text = text
    end
  end
  
  class DCSingleSubtitle
    attr_reader :time_in, :time_out, :fadeup_time, :fadedown_time, :text_lines
    def initialize( time_in, time_out, fadeup_time, fadedown_time, text_lines )
      @time_in = time_in
      @time_out = time_out
      @fadeup_time = fadeup_time
      @fadedown_time = fadedown_time
      @text_lines = text_lines
    end
  end
  
  # DCSubtitle is not defined by a schema but by DTD
  class DC_SUBTITLE
    def initialize( subtitle_id, movie_title, reel_number, language, font_id, font_uri, font_size, font_weight, font_color, font_effect, font_effect_color, subtitle_list, dcp_functions )
      @dcp_functions = dcp_functions
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
	xml.DCSubtitle_( 'Version' => "1.0" ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } DCSubtitle -->"
	  xml.SubtitleID_ subtitle_id
	  xml.Movietitle_ movie_title
	  xml.ReelNumber_ reel_number
	  xml.Language_ language
	  xml.LoadFont_( "Id" => font_id, "URI" => font_uri ) 
	  xml.Font_("Size" => font_size, "Weight" => font_weight, "Id" => font_id, "Color" => font_color, 
	             "Effect" => font_effect, "EffectColor" => font_effect_color) {
	    subtitle_list.each_with_index do |st, i|
	      xml.Subtitle_("SpotNumber" => i + 1, "TimeIn" => st.time_in, "TimeOut" => st.time_out,
	                     "FadeUpTime" => st.fadeup_time, "FadeDownTime" => st.fadedown_time ) {
	        st.text_lines.each do |t|
		  xml.Text_("VAlign" => t.valign, "HAlign" => t.halign, "HPosition" => t.hpos, "VPosition" => t.vpos) {
		    xml.text t.text
	          } # Text_
	        end # st.text_lines.each
	      } # Subtitle_
	    end # subtitle_list.each do
	  } # Font_                                                               
	} # DCSubtitle_
      end # @builder
    end # def initialize
    def xml
      @builder.to_xml( :indent => 2 )
    end # def 
  end # class

  # FIXME only single line subtitles are possible here.
  # Assets here are objects of type DCPAsset.
  #
  # Wolfgang yours was incomplete (missing text node in Subtitle_) and had a typing error (ContentTitleText_).
  #
  # Not yet tested.
  class DCST_SMPTE_428_7_2007
    def initialize( subtitle_reel_id, content_title_text, annotation_text, reel_number, language, edit_rate, time_code_rate, start_time, fonts, default_font_color_code, default_font_name, default_font_size, default_font_weight, subtitles, dcp_functions  )
      @dcp_functions = dcp_functions
      issue_date = DateTime.now.to_s
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
	xml.SubtitleReel_( 'xmlns:dcst' => "http://www.smpte-ra.org/schemas/428-7/2007/DCST", 'xmlns:xs' => "http://www.w3.org/2001/XMLSchema", 'targetNamespace' => "http://www.smpte-ra.org/schemas/428-7/2007/DCST", 'elementFormDefault' => "qualified", 'attributeFormDefault' => "unqualified" ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } smpte dcst -->"
	  xml.Id_ "urn:uuid:#{ subtitle_reel_id }"
	  xml.ContentTitleText_ content_title_text
	  xml.AnnotationText_ annotation_text
	  xml.IssueDate_ issue_date
	  xml.ReelNumber_ reel_number
	  xml.Language_ language
	  xml.EditRate_ edit_rate
	  xml.TimeCodeRate_ time_code_rate
	  xml.StartTime_ start_time
	  # fonts = [ [font, id], [font, id], ... ]
	  fonts.each do |font|
	    xml.LoadFont_( "urn:uuid:#{ font[ 1 ] }", 'ID' => font[ 0 ] )
	  end # fonts.each
	  xml.SubtitleList_ {
	    xml.Font_( 'Color' => default_font_color_code, 'ID' => default_font_name, 'Size' => default_font_size, 'Weight' => default_font_weight ) {
	      # subtitles = [ [tc_in, tc_out, fade_up, fade_down, text], [...] ]
	      subtitles.each_with_index do |subtitle, index|
		xml.Subtitle_( 'SpotNumber' => index + 1, 'TimeIn' => subtitle[ 0 ], 'TimeOut' => subtitle[ 1 ], 'FadeUpTime' => subtitle[ 2 ], 'FadeDownTime' => subtitle[ 3 ] ) {
	           xml.text( subtitle[ 4 ] )
		}
	      end # subtitles.each
	    } # Font
	  } # SubtitleList
	} # SubtitleReel
      end # @builder
    end # initialize
    
    def xml
      @builder.to_xml( :indent => 2 )
    end # def 
  end # DCST_SMPTE_428_7_2007 
  
  class CPL_GENERIC
    attr_reader :uuid
    def initialize( cpl_uuid, dcp_reels, dcp_common_info, content_title, content_kind, content_version_id, content_version_label, rating_list, dcp_functions )
      @logger = Logger::Logger.instance
      @dcp_functions = dcp_functions
      @logger.debug("CPL_GENERIC init: content_version_id = #{ content_version_id }")
      issue_date = DateTime.now.to_s
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
	xml.CompositionPlaylist_( :xmlns => @dcp_functions.cpl_ns, 'xmlns:dsig' => @dcp_functions.ds_dsig ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } #{@dcp_functions.dcp_kind} cpl -->"
	  xml.Id_ "urn:uuid:#{ cpl_uuid }"
	  xml.AnnotationText_ dcp_common_info.annotation
	  xml.IssueDate_ issue_date
	  xml.Issuer_ dcp_common_info.issuer
	  xml.Creator_ dcp_common_info.creator
	  xml.ContentTitleText_ content_title
	  xml.ContentKind_ content_kind
	
	  @dcp_functions.content_version_fragment(content_version_id, content_version_label, xml )
	
	  xml.RatingList_ "#{ rating_list.nil? ? '' : rating_list }"
	  xml.ReelList_ {
	    dcp_reels.each do |dcp_reel|
	                
	      image_asset = dcp_reel.image_asset
	      audio_asset = dcp_reel.audio_asset
	      subtitle_asset = dcp_reel.subtitle_asset
	                
	      xml.Reel_ {
	        @uuid = ShellCommands.uuid_gen
		xml.Id_ "urn:uuid:#{ uuid }" # FIXME
		xml.AssetList_ {
			# TODO intrinsicduration  leader  trailer
	                # Take care. In Reality intrinsic duration is the real length
	                # of the asset, with leader and trailer. YES, we have reels
	                # with leader and trailer like in old 35mm time.
	                # Duration should be intrinsicduration - leader - trailer.
	                # Entrypoint should be the first picture after leader.
	                # We can contribute to this by changing the DCPReel structure in
	                # such a way, that we put assets in the reel.
	                # Each asset has essence, Intrinsicduration (must not be explicite)
	                # and duration
	                # see also the fixme's below
		  if image_asset.stereoscopic
		    xml.MainStereoscopicPicture_( 'xmlns:msp-cpl' => @dcp_functions.cpl_3d_ns ) {
		      mainpicture_fragment(image_asset, xml)                                                                                                      
		    } # MainStereoscopicPicture
		  else
		    xml.MainPicture_ {
	              mainpicture_fragment(image_asset, xml)               
		    } # MainPicture
		  end # if 
		  unless audio_asset.nil?
		    xml.MainSound_ {
		      xml.Id_ "urn:uuid:#{ audio_asset.id }"
		      xml.EditRate_ audio_asset.edit_rate
		      xml.IntrinsicDuration_ audio_asset.intrinsic_duration
		      xml.EntryPoint_ audio_asset.entry_point  # FIXME
		      xml.Duration_ audio_asset.duration
		      if audio_asset.encrypted
			xml.KeyId_ "urn:uuid:#{ audio_asset.key_id }"
			xml.Hash_ audio_asset.asset_hash
		      end # if
		    } # MainSound
		  end # unless
		  unless  subtitle_asset.nil?
	            xml.MainSubtitle_ {
	              # TODO is this xml code OK ???
		      xml.Id_ "urn:uuid:#{ subtitle_asset.id }"  # TODO is this ok ???
		      xml.EditRate_ subtitle_asset.edit_rate
		      xml.IntrinsicDuration_ subtitle_asset.intrinsic_duration
		      xml.EntryPoint_ subtitle_asset.entry_point
		      xml.Duration_ subtitle_asset.duration
		      xml.Hash_ subtitle_asset.asset_hash
	            }  # MainSubtitle
		  end # unless
		} # AssetList
	      } # Reel
	    end # image_mxfs.each
	  } # ReelList
	} # CompositionPlaylist
      end # @builder
    end # initialize

    def xml
      return @builder.to_xml( :indent => 2 )
    end # def 
    
    def check_reels
      nodes = Nokogiri::XML::Document.parse( @builder.to_xml )
      reels = nodes.xpath( '//xmlns:CompositionPlaylist/xmlns:ReelList/xmlns:Reel' )
      puts "Number of reels: #{ reels.size }"
      reels.each_with_index do |reel, index|
	puts "Reel # #{ index + 1 }:"
	puts "Image MXF Id => #{ reel.search( 'AssetList/MainPicture/Id' ).text }"
	puts "Sound MXF Id => #{ reel.search( 'AssetList/MainSound/Id' ).text }"
	# TODO more common, does not print subtitleassets for example
      end # each
    end # check_reels
    
    private
    
    
    def mainpicture_fragment(image_asset, xml)
      xml.Id_ "urn:uuid:#{ image_asset.id }"
      xml.EditRate_ image_asset.edit_rate 
      xml.IntrinsicDuration_ image_asset.intrinsic_duration
      xml.EntryPoint_ image_asset.entry_point
      xml.Duration_ image_asset.duration
      if image_asset.encrypted
	xml.KeyId_ "urn:uuid:#{ image_asset.key_id }"
	xml.Hash_ image_asset.asset_hash
      end
      xml.FrameRate_ image_asset.frame_rate # FIXME SampleRate?
      # correct SMPTE OR MXF INTEROP screen aspect ratio already calculated during creation of image_asset
      xml.ScreenAspectRatio_ image_asset.screen_aspect_ratio
    end

  end # CPL_GENERIC

  class AM_GENERIC
    def initialize( am_uuid, dcp_common_info, assets, dcp_functions )
      @dcp_functions = dcp_functions
      @logger = Logger::Logger.instance
      @am_namespace = @dcp_functions.am_ns
      issue_date = DateTime.now.to_s
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
	xml.AssetMap_( :xmlns => @am_namespace ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } #{@dcp_functions.dcp_kind} am -->"
	  xml.Id_ "urn:uuid:#{ am_uuid }"
	  xml.Creator_ dcp_common_info.creator
	  xml.VolumeCount_ '1' # FIXME
	  xml.IssueDate_ issue_date
	  xml.Issuer_ dcp_common_info.issuer
	  xml.AssetList_ {
	    assets.each do |asset|
	      xml.Asset_ {
		xml.Id_ "urn:uuid:#{ asset.id }"
		if asset.packinglist 
		  xml.PackingList_ 'true'
		end
		xml.ChunkList_ {
		  xml.Chunk_ {
		    xml.Path_ File.basename( asset.asset )  # FIXME Vorsicht: passt nur in diesem speziellen Fall
						      # andrae.steiner@liwest.at
		    # optional: VolumeIndex
		    # optional: Offset
		    # optional: Length
		  } # Chunk
		} # ChunkList
	      } # Asset
	    end # assets.each
	  } # AssetList
	} # AssetMap
      end # @builder
    end # initialize
    
    # Dirty method, because it changes the data type of @builder.
    # But as a Nokogiri greenhorn I do not know another way.
    # Also removing the namespaces and adding the namespace again 
    # is not fine. I do this because add_child adds a default: namespace tag
    # to the nodes added.
    def merge(asset_map)
      doc = Nokogiri::XML::Document.parse( File.read( asset_map ) )
      if doc.search( "//xmlns:AssetMap" ).empty? 
	@logger.debug("File #{asset_map} is no ASSETMAP. returning without merging.")
	return
      end
      xml_assets = Nokogiri::XML( File.read( asset_map ) ).xpath( '/xmlns:AssetMap/xmlns:AssetList/*' )
      @builder = Nokogiri::XML( @builder.to_xml )
      @builder.at( '/xmlns:AssetMap/xmlns:AssetList').add_child( xml_assets )
      @builder.remove_namespaces!
      @builder.root.add_namespace_definition(nil, @am_namespace)
      self
    end
    
    def xml
      return @builder.to_xml( :indent => 2 )
    end

  end # class AM_GENERIC

  
end
