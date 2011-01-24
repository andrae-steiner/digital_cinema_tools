# 
module DCSignature
  
  require 'ShellCommands'
  ShellCommands = ShellCommands::ShellCommands
  
  class DCSignature
    def initialize( xml_to_sign, signer_key_file, ca_cert_file, intermediate_cert_file, certificate_chain )
      signing_cert = certificate_chain.first
      doc = Nokogiri::XML( xml_to_sign ) { |x| x.noblanks } # Thanks, Aaron Patterson
      @builder_signature_template = Nokogiri::XML::Builder.with( doc.at( doc.root.node_name ) ) do |xml|
	xml.Signer_ {
	  xml[ 'dsig' ].X509Data_ {
	    xml.X509IssuerSerial_ {
	      xml.X509IssuerName_ transform_cert_name( signing_cert.issuer )
	      xml.X509SerialNumber_ signing_cert.serial.to_s
	    } # X509IssuerSerial
	    xml.X509SubjectName_ transform_cert_name( signing_cert.subject ) # informational
	  } # X509Data
	} # Signer
	# signature template:
	xml[ 'dsig' ].Signature_ {
	  xml.SignedInfo_ {
	    xml.CanonicalizationMethod_( 'Algorithm' => 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315' )
	    xml.SignatureMethod_( 'Algorithm' => 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256' )
	    xml.Reference_( 'URI' => "" ) {
	      xml.Transforms_ {
		xml.Transform_( 'Algorithm' => 'http://www.w3.org/2000/09/xmldsig#enveloped-signature' )
	      } # Transforms
	      xml.DigestMethod_( 'Algorithm' => 'http://www.w3.org/2000/09/xmldsig#sha1' )
	      xml.DigestValue_
	    } # Reference
	  } # SignedInfo
	  xml.SignatureValue_
	  xml[ 'dsig' ].KeyInfo_ {
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

      @logger = Logger::Logger.instance
      @logger.debug( "Signer key file:  #{ signer_key_file }    " )
      @logger.debug( "ca_cert_file:           #{ ca_cert_file }" )
      @logger.debug( "intermediate_cert_file: #{ intermediate_cert_file }" )
      @logger.debug( "tmp.path: #{ tmp.path }" )
      
      # FIXME hardcoded certificate chain size
      @signed_xml = ShellCommands.xmlsec_command( signer_key_file, ca_cert_file, intermediate_cert_file , tmp.path)
      #
      
    end # initialize
    
    def xml
      @signed_xml
    end
  end # DCSignature
end