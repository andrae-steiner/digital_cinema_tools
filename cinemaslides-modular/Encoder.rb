module Encoder
  
  require 'ShellCommands'
  ShellCommands = ShellCommands::ShellCommands

    class Encoder
      def initialize(size, stereo, fps)
	@size = size
	@fps = fps
      end
      def encode(file, asset)
	raise NotImplementedError, "Do not instanciate this abstract class: Encoder"
      end
    end
    
    class Openjpeg_Tm_Encoder < Encoder
      def initialize(size, stereo, fps)
	super(size, stereo, fps)
      end
      def encode(file, asset)
	ShellCommands.opendcp_j2k_command( file, asset, fps )
      end
    end
    
    class Kakadu_Encoder < Encoder
      def initialize(size, stereo, fps)
	super(size, stereo, fps)
	if size == "2k"
	  @profile = "CINEMA2K"
	elsif size == "4k"
	  @profile = "CINEMA4K"
	end
	@max_bytes_per_image, @max_bytes_per_component = jpeg2000_dcp_rate_constraints( stereo ? 48.0 : fps )
      end
      def encode(file, asset)
	ShellCommands.kakadu_encode_command( file, asset, @profile, @max_bytes_per_component, @max_bytes_per_component)
      end
      
      private 
      
      def jpeg2000_dcp_rate_constraints( fps ) # returns bytes
	dcp_max_bps = 250000000
	max_per_image = ( dcp_max_bps / 8 / fps ).floor
	max_per_component = ( max_per_image / 1.25 ).floor
	return max_per_image, max_per_component
      end
      
    end
    
    class Openjpeg_Encoder < Encoder
      def initialize(size, stereo, fps)
	super(size, stereo, fps)
	if size == "2k"
	  @profile = "cinema2K #{ stereo ? 48 : fps }"
	elsif size == "4k"
	  @profile = "cinema4K"
	end
      end
      def encode(file, asset)
	ShellCommmand.image_to_j2k_command( file, asset, @profile )
      end
    end


end