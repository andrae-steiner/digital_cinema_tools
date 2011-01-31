module KDM_Gen
      
  require 'ShellCommands'
  require 'X509Certificate'
  require 'KDM_SMPTE_430_1_2006'
  require 'DCSignatureKDM'
  require 'SMPTE_DCP'
  
  ShellCommands = ShellCommands::ShellCommands
  CPL_XSD = "/home/home-10.1/Documents/Programmkino/wolfgangw-digital_cinema_tools-6a03857/xsd/SMPTE-429-7-2006-CPL.xsd"

  class KDM_CPL_Info
    attr_reader :cpl_uuid, :content_title_text, :key_ids_types, :content_authenticator
    def initialize ( doc )
      @doc = doc
      @logger = Logger::Logger.instance
      # removing namespaces feels broken right there.
      # makes the KeyId searches in reels set below work, though,
      # whereas searches with ns prefixes wouldn't
      # FIXME reference counter for keys
      doc.remove_namespaces!
      @cpl_uuid = doc.xpath( '//CompositionPlaylist/Id' ).text.split( ':' ).last
      @content_title_text = doc.xpath( '//CompositionPlaylist/ContentTitleText' ).text
      @logger.info( "Content title: #{ @content_title_text }" )
      @logger.debug( "CPL UUID: #{ @cpl_uuid }" )
      
      reels = doc.xpath( '//CompositionPlaylist/ReelList/Reel' )
      @logger.debug( "CPL has #{ reels.size } reel#{ ( reels.size > 1 or reels.size == 0 ) ? 's' : '' }" )
      
      @key_ids_types = Array.new
      reels.each_with_index do |reel, index|
	reel_id = reel.xpath( "Id" ).text.split( ':' ).last
	@logger.debug( "Reel # #{ index + 1 } (#{ reel_id })" )
	SMPTE_DCP::CPL_ASSET_TYPES.each do |assetname|
	  key = key_id_type_for( assetname, reel )
	  next if key.nil?
	  if @key_ids_types.include?( key )
	    @logger.debug( '   <Key seen>' )
	  else
	    @key_ids_types << key
	  end
	end
      end
      
      @content_authenticator = signer_cert_thumbprint
      
    end

    private
    
    # needs to be fixed in due time (signature context cleanup)
    # right now this assumes that the first certificate is the signer's certificate
    # specs allow for any order
    def signer_cert_thumbprint
      @doc.remove_namespaces!
      certs = @doc.xpath( '//CompositionPlaylist/Signature/KeyInfo/X509Data/X509Certificate' )
      @logger.debug( "CPL carries #{ certs.size } certificates" )
      signer_cert = "-----BEGIN CERTIFICATE-----\n" + certs.first.text + "\n-----END CERTIFICATE-----\n"
      tmp = Tempfile.new( 'cinemaslides-' )
      tmpfile = File.open( tmp.path, 'w' ) { |f| f.write signer_cert; f.close }
      thumbprint = dc_thumbprint( tmp.path )
      @logger.debug( "CPL signer certificate thumbprint: #{ thumbprint }" )
      return thumbprint
    end
    
    def key_id_type_for( assetname, node )
      key_id = node.xpath( "AssetList/#{ assetname }/KeyId" ).text.split( ':' ).last
      unless key_id.nil?
	type = key_types[ assetname ]
	key_type_id = Hash.new
	key_type_id[ key_id ] = type
	@logger.debug( "   #{ type } => #{ key_id }" )
	return key_type_id
      end
    end

  end

  class Recipient
    attr_reader :cert_obj, :cert_thumbprint, :cn_name, :description
    def initialize (kdm_target)
      @logger = Logger::Logger.instance
      @cert_obj = OpenSSL::X509::Certificate.new( File.read( kdm_target ) )
      @cert_thumbprint = dc_thumbprint( kdm_target )
      @cn_name = 'TEST'
      # make target name for kdm filename and print RDN info
      @logger.debug( "Target:" )
      @cert_obj.subject.to_a.each do |rdn|
	@logger.debug( "   #{ [ rdn[ 0 ], rdn[ 1 ] ].join( '=' ) }" )
	if rdn[ 0 ] == 'CN'
	  @cn_name = rdn[ 1 ].split( /^([^.]+.)/ ).last # Not sure. This is supposed to pick up everything after the first dot
	  @logger.debug( "Target device name: #{ cn_name }" )
	end
      end
      @description = @cn_name
    end
  end
  
  class KDMCreator
    attr_reader :annotation, :issuer, :kdm_cpl, :kdm_start, :kdm_end, :kdm_target, :verbosity
    def initialize(annotation, issuer, kdm_cpl, kdm_start, kdm_end, kdm_target, verbosity, output_type_obj)
      @annotation = annotation
      @issuer = issuer
      @kdm_cpl = kdm_cpl
      @kdm_start = kdm_start
      @kdm_end = kdm_end 
      @kdm_target = kdm_target
      @verbosity = verbosity
      @output_type_obj = output_type_obj
      @logger = Logger::Logger.instance
      @logger.set_prefix_verbosity( prefix = 'kdm *', @verbosity )
    end
      
    def create_KDM
      
      exit if !@output_type_obj.all_mandatory_tools_available?

      # failure of any of the following checks is reason to exit
      kdm_no_go = Array.new
      kdm_issue_date = DateTime.now
      
      # set up signature context
      # FIXME check availability and validity of certificates/keys
      # FIXME include verification of certchain and matrjoschka-contained validity periods
      if ENV[ 'CINEMACERTSTORE' ].nil?
	@logger.info( "Expecting certificates at $CINEMACERTSTORE. Set this environment variable with 'export CINEMACERTSTORE=<path>'" )
	@logger.info( "Run make-dc-certificate-chain.rb in that directory to create the required certificates." )
	@logger.info( "Sorry for the inconvenience. Work in progress" )
	kdm_no_go << 'CINEMACERTSTORE not set'
      else
	cinamecertstore = ENV[ 'CINEMACERTSTORE' ]
	@logger.debug( "CINEMACERTSTORE is set to #{ cinamecertstore }" )
	if File.is_directory?( cinamecertstore )
	  
	  @signature_context = X509Certificate::X509CertificateChain.new(cinamecertstore)
	  
	  signer_cert_thumbprint = dc_thumbprint( @signature_context.signer_cert_file )
	  @logger.info( "KDM signer: #{ @signature_context.signer_cert_obj.subject.to_s }" )
	else
	  @logger.info( "CINEMACERTSTORE should point at a directory holding your private signer key and associated certificates" )
	  kdm_no_go << 'CINEMACERTSTORE not a directory'
	end
      end
      
      # check for key directory
      @keysdir = File.join( @output_type_obj.cinemaslidesdir, 'keys' )
      if File.is_directory?( @keysdir )
	@logger.debug( "Content keystore at: #{ @keysdir }" )
      else
	@logger.info( "No content keystore found (Looking for #{ @keysdir })" )
	@logger.info( "#{ $0 } will set it up once it builds an encrypted DCP" )
	kdm_no_go << 'No content keystore'
      end
      
      # check presence and validity of cpl and referenced content keys
      kdm_cpl_info, keys = check_presence_and_validity_of_cpl_and_referenced_content_keys( kdm_no_go )
      
      # check KDM time window
      kdm_not_valid_before = ( DateTime.now + @kdm_start ) # check for valid window
      kdm_not_valid_after = ( DateTime.now + @kdm_end )
      if kdm_not_valid_before > kdm_not_valid_after
	@logger.info( "KDM time window out of order" )
	kdm_no_go << 'KDM time window out of order'
      else
	# defer logger.info to after we have a valid target certificate in order to check containment of time window in the target device's validity period
      end
      
      # check presence and validity of target certificate
      recipient = check_presence_and_validity_of_target_certificate( @signature_context.signer_cert_obj, kdm_not_valid_before, kdm_not_valid_after, kdm_no_go )
      
      
      ### exit now if any of the requirements for KDM generation are not met
      if kdm_no_go.size > 0
	kdm_no_go.each do |error|
	  @logger.info( "Error: #{ error }" )
	end
	@logger.info( "KDM generation skipped. See above" )
	exit
      else
	@logger.info( "KDM requirements all met" )
      end
      
      kdm_message_uuid = ShellCommands.uuid_gen
      kdm_message_annotation = @annotation
      device_list_identifier = ShellCommands.uuid_gen # FIXME

      #
      cipher_data_payloads = Array.new
      kdm_cpl_info.key_ids_types.each do |kit|
	# FIXME
	key = File.read( File.join( @keysdir, kit.keys.first ) ).split( ':' ).last
	key_id = kit.keys.first
	cipher_data_payload = cipher_data_payload_binary_package( 
	  signer_cert_thumbprint,
	  kdm_cpl_info.cpl_uuid,
	  kit.values.first, # key_type (plus yeah, i know, idiotic data type chosen for key_ids_types. i'll make up my mind wrt how and where to get key type from)
	  key_id,
	  kdm_not_valid_before.to_s,
	  kdm_not_valid_after.to_s,
	  key
	)
	tmp = Tempfile.new( 'cinemaslides-' )
	tmpfile = File.open( tmp.path, 'w' ) { |f| f.write cipher_data_payload ; f.close }
	@logger.debug( "Encrypt payload for content key ID #{ key_id }" )
	# targeting ...
	cipher_data_payload_encrypted_b64 = ShellCommands.openssl_rsautl_base_64( @kdm_target, tmp.path).chomp
	cipher_data_payloads << cipher_data_payload_encrypted_b64
      end
	
      # KDM data and template for signature
      @logger.debug( 'Prepare KDM XML for signature' )
      kdm_xml = KDM_SMPTE_430_1_2006::KDM_SMPTE_430_1_2006.new(
	kdm_message_uuid,
	kdm_message_annotation,
	kdm_issue_date.to_s,
	@signature_context.signer_cert_obj,
	recipient.cert_obj,
	kdm_cpl_info.cpl_uuid,
	kdm_cpl_info.content_title_text,
	kdm_cpl_info.content_authenticator,
	kdm_not_valid_before,
	kdm_not_valid_after,
	device_list_identifier,
	recipient.description,
	recipient.cert_thumbprint,
	keys,
	cipher_data_payloads
      ).xml
      
      # Sign and write kdm to disk
      @logger.debug( 'Sign and write KDM to disk' )

      kdm_signed_xml = DCSignatureKDM::DCSignatureKDM.new( 
	kdm_xml,
	@signature_context.signer_key_file,
	@signature_context.ca_cert_file,
	@signature_context.intermediate_cert_file,
	@signature_context.certchain_objs
      ).xml
      
      kdm_cpl_content_title = kdm_cpl_info.content_title_text.upcase.gsub( ' ', '-' )[0..19]
      kdm_creation_facility_code = @issuer.upcase.gsub( ' ', '' )[0..2]
      kdm_file = "k_#{ kdm_cpl_content_title }_#{ recipient.cn_name }_#{ yyyymmdd( kdm_not_valid_before ) }_#{ yyyymmdd( kdm_not_valid_after ) }_#{ kdm_creation_facility_code }_OV_#{ kdm_message_uuid[0..7] }.xml"
      if File.exists?( kdm_file )
	@logger.info( "KDM exists: #{ kdm_file }" )
	@logger.info( "4 bytes UUID collision: #{ kdm_message_uuid }. Not overwriting" )
	exit
      else
	File.open( kdm_file, 'w' ) { |f| f.write( kdm_signed_xml ) }
	@logger.info( "Pick up KDM at #{ kdm_file }" )
	@logger.info( 'KDM done' )
      end
    
    end # create_KDM

    
    private
    
    def check_presence_and_validity_of_cpl_and_referenced_content_keys( kdm_no_go )
      
      # check presence and validity of cpl and referenced content keys
      if @kdm_cpl == NIL
	@logger.info( "No CPL specified. Use --cpl <CPL>" )
	kdm_no_go << 'No CPL'
      else
	# Get CPL info
	if File.is_file?( @kdm_cpl )
	  xml_obj = Nokogiri::XML( File.read( @kdm_cpl ) )
	  xsd = Nokogiri::XML::Schema(File.read(CPL_XSD))
	  if !xsd.valid?(xml_obj)
	    xsd.validate(xml_obj).each do |error|
	      @logger.warn( error.message )
	    end
	    kdm_no_go << 'Invalid XML in CPL'
	  else
	    @logger.debug("CPL XML valid.")
	  end
	  if xml_obj.root == NIL
	    @logger.info( "#{ @kdm_cpl } is not XML" )
	    kdm_no_go << 'No CPL'
	  else
	    if xml_obj.root.node_name == 'CompositionPlaylist' # FIXME validation done andrae.steiner@liwest.at
	      @logger.info( "CPL: #{ @kdm_cpl }" )
	      
	      kdm_cpl_info = KDM_CPL_Info.new( xml_obj )
		  
	      if kdm_cpl_info.key_ids_types.size == 0
		@logger.info( "KDM not applicable: #{ @kdm_cpl } doesn't reference content keys" )
		kdm_no_go << 'No content keys referenced in CPL'
	      else
		@logger.info( "CPL references #{ kdm_cpl_info.key_ids_types.size } content key#{ ( kdm_cpl_info.key_ids_types.size != 1 ) ? 's' : '' }" )
		# check presence and local specs compliance of content keys
		@logger.info( "Checking content keys ..." )
		keys = Array.new
		keys_missing = 0
		keys_invalid = 0
		kdm_cpl_info.key_ids_types.each do |kit|
		  if File.exists?( File.join( @keysdir, kit.keys.first ) )
		    candidate_key = File.read( File.join( @keysdir, kit.keys.first ) )
		    if key_spec_valid?( candidate_key )
		      @logger.debug( "   Found: #{ kit.keys.first }" )
		      keys << candidate_key
		    else
		      @logger.info( "Key file #{ kit.keys.first } doesn't fit specs: <UUID>:<Key type>:<Key>" )
		      keys_invalid += 1
		    end
		  else
		    @logger.info( "   Not found: #{ kit.keys.first }" )
		    keys_missing += 1
		  end
		end
		if keys_missing > 0
		  @logger.info( "Keys not found: #{ keys_missing }/#{ kdm_cpl_info.key_ids_types.size }" )
		  kdm_no_go << 'Content key(s) missing'
		end
		if keys_invalid > 0
		  @logger.info( "Key specs invalid: #{ keys_invalid }/#{ kdm_cpl_info.key_ids_types.size }" )
		  kdm_no_go << 'Content key(s) not valid'
		end
		if keys_missing + keys_invalid == 0
		  @logger.info( "All content keys present" )
		end
	      end
	    else
	      @logger.info( "#{ @kdm_cpl } is not a composition playlist" )
	      kdm_no_go << 'No CPL'
	    end
	  end
	else
	  @logger.info( 'Specify a valid XML file' )
	  kdm_no_go << 'No CPL'
	end
	return kdm_cpl_info, keys
      end
      
    end #check_presence_and_validity_of_cpl_and_referenced_content_keys
    
    def check_presence_and_validity_of_target_certificate( signer_cert_obj, kdm_not_valid_before, kdm_not_valid_after, kdm_no_go )
      # check presence and validity of target certificate
      if @kdm_target == NIL
	@logger.info( "No target certificate specified. Use --target <certificate>" )
	kdm_no_go << 'No target'
      else
	if !File.is_directory?( @kdm_target )
	  begin
	    recipient = Recipient.new( @kdm_target)
		    
	    # signer cert valid during requested time window?
	    if time_to_datetime( signer_cert_obj.not_before ) < kdm_not_valid_before and time_to_datetime( signer_cert_obj.not_after ) > kdm_not_valid_after
	      @logger.info( "Signer certificate is valid during requested KDM time window" )
	    else
	      @logger.info( "Signer certificate's validity period does not contain requested KDM time window" )
	      @logger.info( "   valid from  #{ time_to_datetime( signer_cert_obj.not_before ).to_s }" )
	      @logger.info( "   valid until #{ time_to_datetime( signer_cert_obj.not_after ).to_s }" )
	      kdm_no_go << 'Signer certificate validity'
	    end
	    # target cert valid during requested time window?
	    if time_to_datetime( recipient.cert_obj.not_before ) < kdm_not_valid_before and time_to_datetime( recipient.cert_obj.not_after ) > kdm_not_valid_after
	      @logger.info( "Target certificate is valid during requested KDM time window" )
	    else
	      @logger.info( "Target certificate's validity period does not contain requested KDM time window" )
	      @logger.info( "   valid from  #{ time_to_datetime( recipient.cert_obj.not_before ).to_s }" )
	      @logger.info( "   valid until #{ time_to_datetime( recipient.cert_obj.not_after ).to_s }" )
	      kdm_no_go << 'Target certificate validity'
	    end
	    # deferred from KDM time window check
	    @logger.info( "KDM requested valid from  #{ datetime_friendly( kdm_not_valid_before ) }" )
	    @logger.info( "KDM requested valid until #{ datetime_friendly( kdm_not_valid_after ) }" )

	  rescue OpenSSL::X509::CertificateError => e # recipient.cert_obj.class == NilClass
	    @logger.info( "#{ @kdm_target }: #{ e.message }" )
	    kdm_no_go << 'Target OpenSSL::X509::CertificateError'
	  end
	else
	  @logger.info( 'Specify a valid target certificate in PEM format' )
	  kdm_no_go << 'No target'
	end
      end
      return recipient
    end #check_presence_and_validity_of_target_certificate

    def key_spec_valid?( candidate )
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:(MDIK|MDAK|MDSK):[0-9a-f]{32}/.match( candidate ) != NIL
    end
    
  end  # KDMCreator
 
  
end # module