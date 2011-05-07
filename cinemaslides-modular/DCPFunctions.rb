module DCPFunctions
  class DCPFunctions
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
  end
  
  class InterOpDCPFunctions < DCPFunctions
    def initialize
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
    def am_file( dir )
      File.join( dir, 'ASSETMAP.xml' )
    end
    def mxf_UL_value_option
      " "
    end
  end
  end
  
  class SMPTEDCPFunctions < DCPFunctions
    def initialize
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
    def am_file( dir )
      File.join( dir, 'ASSETMAP' )
    end
    def mxf_UL_value_option
      "-L"
    end
 end
  end


end

