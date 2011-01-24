module KDM_SMPTE_430_1_2006
  # FIXME got cornered by a (weak) prototyping decision concerning keyfile format.
  # FIXME thus keys (format '<key id>:<key type>:<key data>') are passed in here 
  # FIXME when all we need for KeyIdList is type and id.
  # FIXME will merge with cipher_data_payloads to pass in a list of all those.
  class KDM_SMPTE_430_1_2006 # see SMPTE 430-3-2008 ETM and SMPTE 430-1-2006 KDM
    def initialize( message_uuid, message_annotation, issue_date, signing_cert, recipient_cert, cpl_uuid, cpl_content_title_text, cpl_content_authenticator, kdm_not_valid_before, kdm_not_valid_after, device_list_identifier, device_list_description, device_cert_thumbprint, keys, cipher_data_payloads )
      # FIXME Nokogiri does not support :standalone
      @builder = Nokogiri::XML::Builder.new( :encoding => 'UTF-8' ) do |xml|
	xml.DCinemaSecurityMessage_( 'xmlns' => 'http://www.smpte-ra.org/schemas/430-3/2006/ETM', 'xmlns:ds' => 'http://www.w3.org/2000/09/xmldsig#', 'xmlns:enc' => 'http://www.w3.org/2001/04/xmlenc#' ) {
	  xml<< "<!-- #{ AppName } #{ AppVersion } smpte kdm -->"
	  xml.AuthenticatedPublic_( 'Id' => 'ID_AuthenticatedPublic' ) {
	    xml.MessageId_ "urn:uuid:#{ message_uuid }"
	    # see SMPTE 430-1-Am1-2009 (D-Cinema Operations - Key delivery message - Amendment 1)
	    # for an informative note regarding MessageType:
	    #   Informative Note: The MessageType value "http://www.smpte-ra.org/430-1/2006/KDM#kdm-key-type" 
	    #   is legal and correct, but, in the event a future revision of the KDM specification requires 
	    #   a revision to the MessageType value, the MessageType value should follow the pattern 
	    #   http://www.smpte-ra.org/430-1/2006/KDM and match the target namespace of the schema.
	    # The amended MessageType value triggers errors on some cinema servers, hence roll back to
	    xml.MessageType_ 'http://www.smpte-ra.org/430-1/2006/KDM#kdm-key-type'
	    xml.AnnotationText_ message_annotation
	    xml.IssueDate_ issue_date
	    xml.Signer_ {
	      xml[ 'ds' ].X509IssuerName_ transform_cert_name( signing_cert.issuer )
	      xml[ 'ds' ].X509SerialNumber_ signing_cert.serial.to_s
	    } # Signer
	    xml.RequiredExtensions_ {
	      xml.KDMRequiredExtensions_( :xmlns => 'http://www.smpte-ra.org/schemas/430-1/2006/KDM' ) {
		xml.Recipient_ {
		  xml.X509IssuerSerial_ {
		    xml[ 'ds' ].X509IssuerName_ transform_cert_name( recipient_cert.issuer )
		    xml[ 'ds' ].X509SerialNumber recipient_cert.serial.to_s
		  } # X509IssuerSerial
		  xml.X509SubjectName_ transform_cert_name( recipient_cert.subject )
		} # Recipient
		xml.CompositionPlaylistId_ "urn:uuid:#{ cpl_uuid }"
		xml.ContentTitleText_ cpl_content_title_text
		xml.ContentAuthenticator_ cpl_content_authenticator
		xml.ContentKeysNotValidBefore_ kdm_not_valid_before
		xml.ContentKeysNotValidAfter_ kdm_not_valid_after
		xml.AuthorizedDeviceInfo_ {
		  # FIXME ad-hoc DeviceListIdentifier
		  xml.DeviceListIdentifier_ "urn:uuid:#{ device_list_identifier }"
		  xml.DeviceListDescription_ device_list_description
		  xml.DeviceList_ {
		    xml.CertificateThumbprint_ device_cert_thumbprint
		  } # DeviceList
		} # AuthorizedDeviceInfo
		xml.KeyIdList_ {
		  keys.each do |key|
		    # FIXME
		    key_id = key.split( ':' ).first
		    key_type = key.split( ':' )[ 1 ]
		    xml.TypedKeyId_ {
		      # Nokogiri workaround for tags with attributes and content
		      xml.KeyType_( key_type, :scope => 'http://www.smpte-ra.org/430-1/2006/KDM#kdm-key-type' )
		      xml.KeyId_ "urn:uuid:#{ key_id }"
		    } # TypedKeyId
		  end
		} # KeyIdList
		xml.ForensicMarkFlagList_ {
		  # example
		  xml.ForensicMarkFlag_ 'http://www.smpte-ra.org/430-1/2006/KDM#mrkflg-picture-disable'
		  xml.ForensicMarkFlag_ 'http://www.smpte-ra.org/430-1/2006/KDM#mrkflg-audio-disable'
		} # ForensicMarkFlagList
	      } # KDMRequiredExtensions
	    } # RequiredExtensions
	    xml.NonCriticalExtensions_
	  } # AuthenticatedPublic
	  xml.AuthenticatedPrivate_( 'Id' => 'ID_AuthenticatedPrivate' ) {
	    cipher_data_payloads.each do |b64|
	      xml[ 'enc' ].EncryptedKey_( 'xmlns:enc' => 'http://www.w3.org/2001/04/xmlenc#' ) {
		xml[ 'enc' ].EncryptionMethod_( 'Algorithm' => 'http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p' ) {
		  xml[ 'ds' ].DigestMethod_( 'xmlns:ds' => 'http://www.w3.org/2000/09/xmldsig#', 'Algorithm' => 'http://www.w3.org/2000/09/xmldsig#sha1' )
		} # EncryptionMethod
		xml[ 'enc' ].CipherData_ {
		  xml[ 'enc' ].CipherValue_ b64
		} # CipherData
	      } # EncryptedKey
	    end
	  } # AuthenticatedPrivate
	} # DCinemaSecurityMessage
      end # @builder
    end # initialize
    
    def xml
      @builder.to_xml( :indent => 2 )
    end
  end # KDM_SMPTE_430_1_2006
end