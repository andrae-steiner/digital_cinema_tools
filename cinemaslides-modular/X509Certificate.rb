module X509Certificate
  
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

  class X509CertificateChain
    attr_reader :signer_key_file, :signer_cert_file, :signer_cert_obj, :ca_cert_file, :intermediate_cert_file, :certchain_text, :certchain_objs
    def initialize (cinemacertstore)
      @cinemacertstore = cinemacertstore
      
      # FIXME right now this is tightly coupled with make-dc-certificate-chain.rb's output.
      # FIXME hardcoded number and names of signer key, certificates and verified chain.
      # FIXME also there's an unholy mix of certificate files here and certificate objects there.
      @signer_key_file = File.join( @cinemacertstore, 'leaf.key' )
      @ca_cert_file = File.join( @cinemacertstore, 'ca.self-signed.pem' )
      @intermediate_cert_file = File.join( @cinemacertstore, 'intermediate.signed.pem' )
      @signer_cert_file = File.join( @cinemacertstore, 'leaf.signed.pem' )
      @certchain_text = File.read( File.join( @cinemacertstore, 'dc-certificate-chain' ) ) # verified chain [ root, intermediate, leaf ]

      @certs = Array.new
      c = Array.new

      certchain_text.split( /\n/ ).each do |line|
	if line =~ /-----BEGIN CERTIFICATE-----/
	  c = Array.new
	  c << line
	elsif line =~ /-----END CERTIFICATE-----/
	  c << line
	  @certs << OpenSSL::X509::Certificate.new( c.join( "\n" ) + "\n" )
	else
	  c << line
	end
      end
      
      @certs.reverse!
      
      @certchain_objs = @certs
      @signer_cert_obj = @certchain_objs.first
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
    
    # FIXME right now this is tightly coupled with make-dc-certificate-chain.rb's output.
    # FIXME hardcoded number and names of signer key, certificates and verified chain.
    # FIXME also there's an unholy mix of certificate files here and certificate objects there.
    def signature_context
      signer_key_file = File.join( @cinemacertstore, 'leaf.key' )
      ca_cert_file = File.join( @cinemacertstore, 'ca.self-signed.pem' )
      intermediate_cert_file = File.join( @cinemacertstore, 'intermediate.signed.pem' )
      signer_cert_file = File.join( @cinemacertstore, 'leaf.signed.pem' )
      certchain_text = File.read( File.join( @cinemacertstore, 'dc-certificate-chain' ) ) # verified chain [ root, intermediate, leaf ]
      certchain_objs = @certs
      signer_cert_obj = certchain_objs.first
      return signer_key_file, signer_cert_file, signer_cert_obj, ca_cert_file, intermediate_cert_file, certchain_text, certchain_objs
    end


    # FIXME auch in initialize integrieren andrae.steiner@liwest.at
    # 
    # @cinemacertstore is set. check if it points at something useable
    def generic_signature_context
      files = Dir.glob( File.join( @cinemacertstore, '*.pem' ) )
      certs = Array .new
      root_ca = NIL
      
      files.each do |file|
	if File.ftype( file ) == 'file'
	  begin
	    certs << OpenSSL::X509::Certificate.new( File.read( file ) )
	    @logger.debug( certs.last.subject.to_s )
	  rescue OpenSSL::X509::CertificateError => e
	    puts e.message
	  end
	else
	  @logger.debug( "Skip #{ file }" )
	end
      end
      
      certs.each do |cert|
	if cert.issuer == cert.subject
	  # root candidate. tbc
	else
	  # intermediate or leaf. tbc
	end
      end
      
    end

    
    
  end # X509CertificateChain

end