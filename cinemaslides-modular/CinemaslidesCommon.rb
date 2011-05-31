module CinemaslidesCommon
  require 'Logger'
  
    # calculate indices of array source for multithreading
    # so that  source can be divided into equal parts and be
    # fed into the threads
    def CinemaslidesCommon::split_indices(source)
      logger = Logger::Logger.instance
      n_threads = OptParser::Optparser.get_options.n_threads
      indices = Array.new
      n_elements = source.length/n_threads
      remainder = source.length%n_threads      
      if (n_elements == 0) 
	remainder.times do |i|
	  indices << [i,i]
	end
      else
	len2 = source.length+n_threads-1
	(n_threads-remainder).times do |i|
	  start_index = i*(len2/n_threads)
	  end_index   = (i == (n_threads - 1)) ? source.length - 1 : (i + 1)*(len2/n_threads) - 1
	  indices << [start_index, end_index]
	end
	remainder.times do |i|
	  f = i + n_threads-remainder
	  start_index = f*(len2/n_threads) - i
	  end_index   = (f == (n_threads - 1)) ? source.length - 1 : (f + 1)*(len2/n_threads) - 1 - (i + 1)
	  indices << [start_index, end_index]
	end
      end
      return indices
    end


  
end
