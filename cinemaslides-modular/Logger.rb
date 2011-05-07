module Logger
  
  VERBOSITY_CHOICE_QUIET = 'quiet'
  VERBOSITY_CHOICE_INFO  = 'info'
  VERBOSITY_CHOICE_DEBUG = 'debug'


  class Logger
  attr_accessor :prefix
  def initialize( prefix, verbosity )
    @verbosity = verbosity
    @critical = TRUE
    case @verbosity
    when VERBOSITY_CHOICE_QUIET
      @info = FALSE
      @warn = FALSE
      @debug = FALSE
    when VERBOSITY_CHOICE_INFO
      @info = TRUE
      @warn = TRUE
      @debug = FALSE
    when VERBOSITY_CHOICE_DEBUG
      @info = TRUE
      @warn = TRUE
      @debug = TRUE
    end
    @prefix = prefix
    @color = Hash.new
    # these work ok on a black background:
    @color[:info] = ''
    @color[:debug] = '32'
    @color[:warn] = '33'
    @color[:critical] = '1'
  end
  def set_prefix_verbosity( prefix, verbosity )
    initialize( prefix, verbosity )
  end
  
  @@instance = Logger.new(prefix = "*", VERBOSITY_CHOICE_INFO)

  def self.instance
    return @@instance
  end
  

  
  def info( text )
    to_console( @color[:info], text ) if @info == TRUE
  end
  def warn( text )
    to_console( @color[:warn], text ) if @warn == TRUE
  end
  def debug( text )
    to_console( @color[:debug], text ) if @debug == TRUE
  end
  def critical( text )
    to_console( @color[:critical], text ) if @critical == TRUE
  end
  def cr( text )
    carriage_return( @color[:info], text ) unless @verbosity == VERBOSITY_CHOICE_QUIET
  end
  def carriage_return( color, text )
    printf "\033[#{ color }m#{ @prefix } #{ text }\033[0m#{ ' ' * 24 }\r"; STDOUT.flush
  end
  def to_console( color, text )
    printf "\033[#{ color }m#{ @prefix } #{ text }\033[0m#{ ' ' * 24 }\n"
  end
  
  private_class_method :new
  
end

end
