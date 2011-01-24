module DCSignatureKDM
  
  require 'ShellCommands'
  ShellCommands = ShellCommands::ShellCommands
  
  class DCSignatureKDM
    def initialize( xml_to_sign, signer_key_file, ca_cert_file, intermediate_cert_file, certificate_chain )
      doc = Nokogiri::XML( xml_to_sign ) { |x| x.noblanks }
      @builder_signature_template = Nokogiri::XML::Builder.with( doc.at( doc.root.node_name ) ) do |xml|
	xml[ 'ds' ].Signature_( 'xmlns:ds' => 'http://www.w3.org/2000/09/xmldsig#' ) {
	  xml.SignedInfo_ {
	    xml.CanonicalizationMethod_( 'Algorithm' => 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315#WithComments' )
	    xml.SignatureMethod_( 'Algorithm' => 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256' )
	    xml.Reference_( 'URI' => '#ID_AuthenticatedPublic' ) {
	      xml.DigestMethod_( 'Algorithm' => 'http://www.w3.org/2001/04/xmlenc#sha256' )
	      xml.DigestValue_
	    } # Reference
	    xml.Reference_( 'URI' => '#ID_AuthenticatedPrivate' ) {
	      xml.DigestMethod_( 'Algorithm' => 'http://www.w3.org/2001/04/xmlenc#sha256' )
	      xml.DigestValue_
	    } # Reference
	  } # SignedInfo
	  xml.SignatureValue_
	  xml.KeyInfo_ {
	    certificate_chain.each do |cert|
	      xml.X509Data_ {
		xml.X509IssuerSerial_ {
		  xml.X509IssuerName_ transform_cert_name( cert.issuer )
		  xml.X509SerialNumber_ cert.serial.to_s
		} # X509IssuerSerial
		xml.X509Certificate stripped( cert.to_pem )
	      } # X509Data
	    end # certs
	  } # KeyInfo
	} # Signature
      end # @builder_signature_template
      
      pre_signed_xml = @builder_signature_template.to_xml( :indent => 2 )
      tmp = Tempfile.new( 'cinemaslides-' )
      tmpfile = File.open( tmp.path, 'w' ) { |f| f.write pre_signed_xml; f.close }
      #File.copy( tmp.path, 'presigned.xml' )

      # FIXME hardcoded certificate chain size
      @signed_xml = ShellCommands.xmlsec_KDM_command( signer_key_file, ca_cert_file, intermediate_cert_file , tmp.path)
      #

    end # initialize
    def xml
      @signed_xml
    end
  end # DCSignatureKDM
end