module TimeDateUtils

  def hours_minutes_seconds_verbose( seconds )
    t = seconds
    hrs = ( ( t / 3600 ) ).to_i
    min = ( ( t / 60 ) % 60 ).to_i
    sec = t % 60
    return [
      hrs > 0 ? hrs.to_s + " hour#{ 's' * ( hrs > 1 ? 1 : 0 ) }" : nil ,
      min > 0 ? min.to_s + " minute#{ 's' * ( min > 1 ? 1 : 0 ) }" : nil ,
      sec == 1 ? sec.to_i.to_s + ' second' : sec != 0 ? sec.to_s + ' seconds' : nil ,
      t > 60 ? "(#{ t } seconds)" : nil
    ].compact.join( ' ' )
  end


  def hms_from_seconds( seconds )
    hours = ( seconds / 3600.0 ).to_i
    minutes = ( ( seconds / 60.0 ) % 60 ).to_i
    secs = seconds % 60
    return [ hours, minutes, secs ].join( ':' )
  end

  def seconds_from_hms( timestring ) # hh:mm:ss.fraction
    a = timestring.split( ':' )
    hours = a[0].to_i
    minutes = a[1].to_i
    secs = a[2].to_f
    return ( hours * 3600 + minutes * 60 + secs )
  end

  def get_timestamp
    #t = Time.now
    #[t.year, '%02d' % t.month, '%02d' % t.day, '%02d' % t.hour, '%02d' % t.min, '%02d' % t.sec].join('_')
    DateTime.now.to_s
  end

  # date helpers
  def time_to_datetime( time ) # OpenSSL's ruby bindings return Time objects for certificate validity info
    DateTime.parse( time.to_s )
  end
  def datetime_friendly( dt ) # return something in the form of "Tuesday Nov 30 2010 (18:56)"
    "#{ DateTime::DAYNAMES[ dt.wday ] } #{ DateTime::ABBR_MONTHNAMES[ dt.month ] } #{ dt.day.to_s } #{ dt.year.to_s } (#{ '%02d' % dt.hour.to_s }:#{ '%02d' % dt.min.to_s })"
  end
  def yyyymmdd( datetime ) # used in KDM filenames. See http://www.kdmnamingconvention.com/
    datetime.to_s.split('T').first.gsub( /-/,'' )
  end


end