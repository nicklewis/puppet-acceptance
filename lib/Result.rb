class Result
  attr_accessor :host, :cmd, :stdout, :stderr, :exit_code
  def initialize(host=nil, cmd=nil, stdout=nil, stderr=nil, exit_code=nil)
    @host      = host
    @cmd       = cmd
    @stdout    = stdout
    @stderr    = stderr
    @exit_code = exit_code
  end

  def log
    Log.debug
    Log.debug "<STDOUT>\n#{stdout}\n</STDOUT>"
    Log.debug "<STDERR>\n#{stderr}\n</STDERR>"
    Log.debug "Exited with #{exit_code}"
  end
end
