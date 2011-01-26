module SMPTE_DCP

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
    attr_reader :asset
    def initialize (asset)
      @asset = asset
      @logger = Logger::Logger.instance
    end # def
  end # class
  
  class DCPSubtitleAsset < DCPAsset
    attr_reader :id, :edit_rate, :asset_hash, :entry_point, :duration, :intrinsic_duration
    def initialize( asset, edit_rate = 0, intrinsic_duration = 0, entry_point = 0, duration = 0)
      super( asset )
      @id = get_subtitle_id(asset) #
      @edit_rate = edit_rate
      @intrinsic_duration = intrinsic_duration
      @entry_point = entry_point
      @duration = duration
      @asset_hash = asdcp_digest( asset ) if !asset.nil?
    end # def 
    
    private 
    
    def get_subtitle_id(asseet)
      xml = Nokogiri::XML( File.open( asset ) )
      id1 = xml.xpath( '//DCSubtitle/SubtitleID' ).text.gsub( ' ', '' )
      if id1.nil?
	id1 = xml.xpath( '//xmlns:SubtitleReel/xmlns:Id' ).textgsub( ' ', '' )
      end # if
      @logger.debug("Subtitle Id = #{ id1 }.")
      id1
    end # def 
    
  end # class
  
  class DCPMXFAsset < DCPAsset
    attr_reader :id, :intrinsic_duration, :key_id, :asset_hash, :encrypted, :stereoscopic
    attr_accessor :entry_point, :duration
    def initialize (asset)
      super(asset)
      @asset_meta = MXF::MXF_Metadata.new( asset ).hash
      @id =  @asset_meta[ MXF::MXF_KEYS_ASSETUUID ]
      @intrinsic_duration = @asset_meta[ MXF::MXF_KEYS_CONTAINER_DURATION ]
      @entry_point = 0
      @duration = @asset_meta[ MXF::MXF_KEYS_CONTAINER_DURATION ]
      @stereoscopic =  @asset_meta.has_key?( MXF::MXF_KEYS_STEREOSCOPIC )
      if @asset_meta.has_key?( MXF::MXF_KEYS_CRYPTOGRAPHIC_KEY_ID )
	@key_id = @asset_meta[ MXF::MXF_KEYS_CRYPTOGRAPHIC_KEY_ID ]
	@asset_hash = asdcp_digest( asset )
	@encrypted = TRUE
      else
	@encrypted = FALSE
      end # if 
    end # def 
  end # class
  
  class DCPMXFAudioAsset < DCPMXFAsset
    attr_reader :edit_rate
    def initialize (asset)
      super(asset)
      @edit_rate =  @asset_meta[ MXF::MXF_KEYS_EDIT_RATE ].to_s.gsub( '/', ' ' )
    end # def 
  end # class
  
  class DCPMXFImageAsset < DCPMXFAsset
    attr_reader :edit_rate, :frame_rate, :screen_aspect_ratio
    def initialize (asset)
      super(asset)
      @edit_rate =  @asset_meta[ MXF::MXF_KEYS_SAMPLE_RATE ].to_s.gsub( '/', ' ' )
      @frame_rate = @asset_meta[ MXF::MXF_KEYS_SAMPLE_RATE ].to_s.gsub( '/', ' ' ) # FIXME SampleRate?
      @screen_aspect_ratio = @asset_meta[ MXF::MXF_KEYS_ASPECT_RATIO ].to_s.gsub( '/', ' ' )
    end # def
  end # class
            
  class DCPReelWithAssets
    attr_reader :image_mxf, :audio_mxf, :subtitle_xml, :image_asset, :audio_asset, :subtitle_asset
    def initialize( image_asset, audio_asset, subtitle_asset = nil )
      @image_asset = image_asset
      @audio_asset = audio_asset
      @subtitle_asset = subtitle_asset
      @audio_mxf = audio_asset.nil? ? nil: audio_asset.asset
      @image_mxf = image_asset.asset
      @subtitle_xml = subtitle_asset.nil? ? nil : subtitle_asset.asset
    end # def 
    def asset_names_to_a
      a = Array.new
      a << @image_mxf
      a << @audio_mxf if !@audio_mxf.nil?
      a << @subtitle_xml if !@subtitle_xml.nil?
      return a
    end # def 
  end # class
      
  
  class SMPTE_DCP
    
  # assume, that the image and audiomxfs are already in the dcpdir
    
    def initialize(dcpdir, issuer, creator, annotation, sign, signature_context)
      @dcp_common_info = DCPCommonInfo.new(issuer, creator, annotation, sign)
      @dcpdir = dcpdir
      @logger = Logger::Logger.instance
      @signature_context = signature_context
      @cpls = Array.new
    end # def 
    
    def add_cpl( dcp_reels, content_title, content_kind, rating_list )      
      cpl_uuid = ShellCommands.uuid_gen # FIXME
      @logger.debug("add_cpl: cpl_uuid = #{ cpl_uuid }")
      content_version_id = cpl_uuid + '_' + DateTime.now.to_s,
      @logger.debug("add_cpl: content_version_id = #{ content_version_id }")
      content_version_label = content_version_id
      cpl = CPL_SMPTE_429_7_2006.new( cpl_uuid, dcp_reels, @dcp_common_info, content_title, content_kind, content_version_id, content_version_label, rating_list )
      if @dcp_common_info.sign
	cpl_new = DCSignature::DCSignature.new( cpl.xml, @signature_context.signer_key_file, @signature_context.ca_cert_file, @signature_context.intermediate_cert_file, @signature_context.certchain_objs )
	cpl = cpl_new
      end # if
      @cpls << CPLInfo.new(cpl_uuid, cpl.xml)
    end # def 
    
    def write_vf_dcp (other_dcp_asset_list)
      # write_vf_dcp = version file dcp
      # PKL: only files of this dir.
      #      if a file is referenced in a cpl and that file is not in this dir
      #      exclude from packinglist. Automatically done.
      # ASSETLIST: assetlist of other_dcp_dir plus assets from this dir
      @cpls.each do |cpl|
	 @logger.info( 'Write CPL' )
	 @logger.debug( "CPL UUID:       #{ cpl.uuid }" )
         cpl_file = File.join( @dcpdir, 'cpl_' + cpl.uuid + '_.xml' )
	 File.open( cpl_file, 'w' ) { |f| f.write( cpl.cpl_xml ) }
      end # each 
      write_pkl
      create_am
      # Write Assetmap
      @logger.info( 'Write ASSETMAP' )
      File.open( @am_file, 'w' ) { |f| f.write( @am.merge(other_dcp_asset_list).xml ) }
    end # def 
    
    def write_ov_dcp
      @cpls.each do |cpl|
	 @logger.info( 'Write CPL' )
	 @logger.debug( "CPL UUID:       #{ cpl.uuid }" )
         cpl_file = File.join( @dcpdir, 'cpl_' + cpl.uuid + '_.xml' )
	 File.open( cpl_file, 'w' ) { |f| f.write( cpl.cpl_xml ) }
      end # each 
      write_pkl
      create_am
      # Write Assetmap
      @logger.info( 'Write ASSETMAP' )
      File.open( @am_file, 'w' ) { |f| f.write( @am.xml ) }
      
    end # def
    
    private 
    
    def write_pkl
      # create PackingList
      @logger.info( 'Create PKL ...' )
      # might be cumulative DCP, end up with 1 pkl to cover all
      obsolete_pkls = Dir.glob( File.join( @dcpdir, 'pkl_*_.xml' ) ) # FIXME check xml for packing list
      obsolete_pkls.each do |obsolete_pkl|
	@logger.debug( "Obsolete:   #{ File.basename( obsolete_pkl ) }" )
	File.delete( obsolete_pkl )
      end # each
      @pkl_assets = Array.new
      
      # TODO future: for subtitles
      @pkl_assets << Dir.glob( File.join( @dcpdir, 'subtitle_*_.xml' ) )
      
      @pkl_assets << Dir.glob( File.join( @dcpdir, 'cpl_*_.xml' ) )
      @pkl_assets << Dir.glob( File.join( @dcpdir, '*_.mxf' ) )
      pkl_uuid = ShellCommands.uuid_gen
      @logger.debug( "PKL UUID:       #{ pkl_uuid }" )
      @pkl_file = File.join( @dcpdir, 'pkl_' + pkl_uuid + '_.xml' )
      @pkl = PKL_SMPTE_429_8_2007.new(
	pkl_uuid,
	@dcp_common_info,
	@pkl_assets.flatten
      )
      if @dcp_common_info.sign
	@pkl = DCSignature::DCSignature.new( @pkl.xml, @signature_context.signer_key_file, @signature_context.ca_cert_file, @signature_context.intermediate_cert_file, @signature_context.certchain_objs )
      end # if
      # Write PackingList
      @logger.info( 'Write PKL ...' )
      File.open( @pkl_file, 'w' ) { |f| f.write( @pkl.xml ) }
    end
    def create_am
      # create Assetmap
      @logger.info( 'Create ASSETMAP' )
      am_assets = Array.new
      am_assets << @pkl_assets
      am_assets << @pkl_file
      am_uuid = ShellCommands.uuid_gen
      @logger.debug( "AM UUID:        #{ am_uuid }" )
      @am_file = File.join( @dcpdir, 'ASSETMAP.xml' )
      @am = AM_SMPTE_429_9_2007.new(
	am_uuid,
	@dcp_common_info,
	am_assets.flatten
      )
    end

  end # class
  
  class PKL_SMPTE_429_8_2007
    # assets here are assetnames
    def initialize( pkl_uuid, dcp_common_info, assets )
      @logger = Logger::Logger.instance
      issue_date = DateTime.now.to_s
      asset_hashes = Hash.new
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
	xml.PackingList_( :xmlns => 'http://www.smpte-ra.org/schemas/429-8/2007/PKL', 'xmlns:dsig' => 'http://www.w3.org/2000/09/xmldsig#' ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } smpte pkl -->"
	  xml.Id_ "urn:uuid:#{ pkl_uuid }"
	  xml.AnnotationText_ dcp_common_info.annotation
	  xml.IssueDate_ issue_date
	  xml.Issuer_ dcp_common_info.issuer
	  xml.Creator_ dcp_common_info.creator
	  xml.AssetList_ {
	    asset_hashes = get_asset_hashes( assets )
	    assets.each do |asset|
	      if File.is_XML_file?(asset)
		mimetype = 'text/xml'
		asset_uuid = Nokogiri::XML( File.open( asset ) ).xpath( "//xmlns:CompositionPlaylist/xmlns:Id" ).text.split( 'urn:uuid:' ).last
	      else
		mimetype = 'application/mxf'
		metadata = MXF::MXF_Metadata.new( asset ).hash
		asset_uuid = metadata[ MXF::MXF_KEYS_ASSETUUID ] 
	      end
	      xml.Asset_ {
		xml.Id_ "urn:uuid:#{ asset_uuid }"
		# optional: AnnotationText per asset
	        xml.Hash_ asset_hashes.has_key?(asset_uuid) ? asset_hashes[ asset_uuid ] : asdcp_digest( asset )
		xml.Size_ File.size( asset )
		xml.Type_ mimetype
		xml.OriginalFileName_ File.basename( asset )
	      } # Asset
	    end # assets.each
	  } # AssetList
	} # PackingList
      end # @builder
    end # initialize
    
    def xml
      return @builder.to_xml( :indent => 2 )
    end # def 
    
    private
    
    def get_asset_hashes( assets )
      # get hashes from the cpls of this dcp, so we do not have to compute them a second time 
      # another possibility would be to store them like the image assets or keys
      # andrae.steiner@liwest.at
      asset_hashes = Hash.new
      assets.each do |asset|
	if File.is_XML_file?(asset)
	  xml_assets = Nokogiri::XML( File.open( asset ) ).xpath( '//xmlns:CompositionPlaylist/xmlns:ReelList/xmlns:Reel/xmlns:AssetList/*' )
	  @logger.debug( "CPL has #{ xml_assets.size } asset#{ ( xml_assets.size > 1 or xml_assets.size == 0 ) ? 's' : '' }" )
	  xml_assets.each_with_index do |single_asset, index|
	    id = single_asset.xpath( "xmlns:Id" ).text.split( ':' ).last
	    hash = single_asset.xpath( "xmlns:Hash" ).text
	    @logger.debug("found id = #{ id }, hash = #{ hash }.") if !id.nil?
	    next if id.nil?
	    if asset_hashes.include?( id )
	      @logger.debug( "   <asset Key seen>: #{ id }" )
	    else
	      asset_hashes[id]= hash 
	    end # if
	  end # each_with_index do
	end # if 
      end # each do
      asset_hashes
    end # def 
    
  end # PKL_SMPTE_429_8_2007
  
  # TODO class DC_SUBTITLE
  # should allow for two line subtitles
  class DC_SUBTITLE
    def initialize( subtitle_id, movie_title, reel_number, language, font_id, font_uri, font_size, font_weight, font_color, font_effect, subtitles )
    end # def 
  end # class

  class DCST_SMPTE_428_7_2007
    def initialize( subtitle_reel_id, content_title_text, annotation_text, reel_number, language, edit_rate, time_code_rate, start_time, fonts, default_font_color_code, default_font_name, default_font_size, default_font_weight, subtitles )
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
		xml.Subtitle_( 'SpotNumber' => index + 1, 'TimeIn' => subtitle[ 0 ], 'TimeOut' => subtitle[ 1 ], 'FadeUpTime' => subtitle[ 2 ], 'FadeDownTime' => subtitle[ 3 ] )
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
  
  class CPL_SMPTE_429_7_2006
    def initialize( cpl_uuid, dcp_reels, dcp_common_info, content_title, content_kind, content_version_id, content_version_label, rating_list )
      @logger = Logger::Logger.instance
      @logger.debug("CPL_SMPTE_429_7_2006 init: content_version_id = #{ content_version_id }")
      issue_date = DateTime.now.to_s
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
	xml.CompositionPlaylist_( :xmlns => 'http://www.smpte-ra.org/schemas/429-7/2006/CPL', 'xmlns:dsig' => 'http://www.w3.org/2000/09/xmldsig#' ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } smpte cpl -->"
	  xml.Id_ "urn:uuid:#{ cpl_uuid }"
	  xml.AnnotationText_ dcp_common_info.annotation
	  xml.IssueDate_ issue_date
	  xml.Issuer_ dcp_common_info.issuer
	  xml.Creator_ dcp_common_info.creator
	  xml.ContentTitleText_ content_title
	  xml.ContentKind_ content_kind
	  xml.ContentVersion_ {
	    xml.Id_ "urn:uri:#{ content_version_id }"
	    xml.LabelText_ content_version_label
	  } # ContentVersion
	  xml.RatingList_ "#{ rating_list.nil? ? '' : rating_list }"
	  xml.ReelList_ {
	    dcp_reels.each do |dcp_reel|
	                
	      image_asset = dcp_reel.image_asset
	      audio_asset = dcp_reel.audio_asset
	      subtitle_asset = dcp_reel.subtitle_asset
	                
	      xml.Reel_ {
		xml.Id_ "urn:uuid:#{ ShellCommands.uuid_gen }" # FIXME
		xml.AssetList_ {
			# TODO intrinsicduration  leader  trailer
	                # Take care. In Reality intrinsic duration is the real length
	                # of the asset, with leader and trailer. YES, we have reels
	                # with leader and trailer like on old 35mm time.
	                # duration should be intrinsicduration - leader - trailer
	                # entrypoint should be the first picture after leader.
	                # We can contribute to this by changing the DCPReel structure in
	                # such a way, that we put assets in the reel.
	                # Each asset has essence, Intrinsicduration (must not be explicite)
	                # and duration
	                # see also the fixme's below
	          mainpicture_proc = Proc.new do|xml|
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
		      xml.ScreenAspectRatio_ image_asset.screen_aspect_ratio
	          end # Proc.new do
		  if image_asset.stereoscopic
		    xml.MainStereoscopicPicture_( 'xmlns:msp-cpl' => 'http://www.smpte-ra.org/schemas/429-10/2008/Main-Stereo-Picture-CPL' ) {
		      mainpicture_proc.call(xml)                                                                                                      
		    } # MainStereoscopicPicture
		  else
		    xml.MainPicture_ {
	              mainpicture_proc.call(xml)               
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
  end # CPL_SMPTE_429_7_2006

  class AM_SMPTE_429_9_2007
    def initialize( am_uuid, dcp_common_info, assets )
      @logger = Logger::Logger.instance
      @am_namespace = 'http://www.smpte-ra.org/schemas/429-9/2007/AM'
      issue_date = DateTime.now.to_s
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
	xml.AssetMap_( :xmlns => @am_namespace ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } smpte am -->"
	  xml.Id_ "urn:uuid:#{ am_uuid }"
	  xml.Creator_ dcp_common_info.creator
	  xml.VolumeCount_ '1' # FIXME
	  xml.IssueDate_ issue_date
	  xml.Issuer_ dcp_common_info.issuer
	  xml.AssetList_ {
	    assets.each do |asset|
	      if File.is_XML_file?(asset)
		doc = Nokogiri::XML::Document.parse( File.read( asset ) )
		if doc.search( "//xmlns:PackingList" ).empty? # FIXME assume CPL
		  packing_list = FALSE
		  asset_uuid = Nokogiri::XML( File.open( asset ) ).xpath( "//xmlns:CompositionPlaylist/xmlns:Id" ).text.split( 'urn:uuid:' ).last
		else
		  packing_list = TRUE
		  asset_uuid = Nokogiri::XML( File.open( asset ) ).xpath( "//xmlns:PackingList/xmlns:Id" ).text.split( 'urn:uuid:' ).last
		end # PackingList?
	      else # MXF
		metadata = MXF::MXF_Metadata.new( asset ).hash
		asset_uuid = metadata[ MXF::MXF_KEYS_ASSETUUID ]
	      end
	      
	      xml.Asset_ {
		xml.Id_ "urn:uuid:#{ asset_uuid }"
		if packing_list 
		  xml.PackingList_ 'true'
		end
		xml.ChunkList_ {
		  xml.Chunk_ {
		    xml.Path_ File.basename( asset )  # FIXME Vorsicht: passt nur in diesem speziellen Fall
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
    
    # dirty method, because it changes the data type of @builder.
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

  end # class AM_SMPTE_429_9_2007

  
end
