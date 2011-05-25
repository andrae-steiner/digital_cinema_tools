module X509Certificate
  
  require 'Certificates'
    

# FIXME expects an ordered certificate chain (pem format) for now:
#
# 1. self-signed root certificate
# 2. intermediate certificate signed by root certificate
# 3. ...
# n. leaf cert signed by previous intermediate 
#
# an ordered certificate chain is created by iterating through your certificates,
# starting with a self-signed root certificate -> verify -> append to (empty) certificate chain
# verify root-signed intermediate certificate -> append ... repeat until leaf certificate.
#
# returns reversed list of OpenSSL::X509::Certificates (leaf, inter, ..., root)
#
# TODO There should be a possibility to enter the names of the certificate files and 
# the private key at the commandline ( --root-cert, --ca-cert, --signer-cert, --signer-key for example)  
  class X509CertificateChain
    attr_reader :signer_cert_obj, :certchain_objs, :signer_key
    def initialize (ca_cert, intermediate_cert, signer_cert, signer_key)
      
      
      # FIXME right now this is tightly coupled with make-dc-certificate-chain.rb's output.
      # FIXME hardcoded number and names of signer key, certificates and verified chain.
      # FIXME also there's an unholy mix of certificate files here and certificate objects there.
      @signer_key = Certificates::SIGNERKEY

      #------------------------
      @certchain_objs = Array.new
      @certchain_objs << OpenSSL::X509::Certificate.new( Certificates::SIGNER_CERT ) <<
			 OpenSSL::X509::Certificate.new( Certificates::INTERMEDIATE_CERT ) <<
			 OpenSSL::X509::Certificate.new( Certificates::CA_CERT)
      @signer_cert_obj = @certchain_objs.first      
      @certs = @certchain_objs
      #------------------------

    end # initialize
    
    def to_a
      @certs
    end
    def []( index )
      @certs[ index ]
    end
    def size
      @certs.size
    end
    
    
  end # X509CertificateChain

end