class TestNotApplicableError < StandardError
end

class TestWrapper
  require 'lib/test_wrapper/host'
  require 'lib/gen_answer_files'

	include GenAnswerFiles

  include Test::Unit::Assertions

  attr_reader :config, :options, :path, :fail_flag, :usr_home, :test_status, :exception
  def initialize(config,options={},path=nil)
    @config  = config['CONFIG']
    @hosts   = config['HOSTS'].collect { |name,overrides| Host.new(name,overrides,@config) }
    @options = options
    @path    = path
    @usr_home = ENV['HOME']
    @test_status = :pass
    @exception = nil
    #
    # We put this on each wrapper (rather than the class) so that methods
    # defined in the tests don't leak out to other tests.
    class << self
      def run_test
        begin
          test = File.read(path)
          eval test,nil,path,1
        rescue Test::Unit::AssertionFailedError => e
          @test_status = :fail
          @exception   = e
        rescue TestNotApplicableError => e
          @test_status = :skipp
          @exception = e
        rescue StandardError, ScriptError => e
          @test_status = :error
          @exception   = e
        end
        classes = test.split(/\n/).collect { |l| l[/^ *class +(\w+) *$/,1]}.compact
        case classes.length
        when 0; self
        when 1; eval(classes[0]).new(config)
        else fail "More than one class found in #{path}"
        end
      end
    end
  end
  #
  # Identify hosts
  #
  def hosts(desired_role=nil)
    @hosts.select { |host| desired_role.nil? or host['roles'].include?(desired_role) }
  end
  def agents
    hosts 'agent'
  end
  def agent
    agents.first
  end
  def masters
    hosts 'master'
  end
  def master
    masters.first
  end
  def dashboards
    hosts 'dashboard'
  end
  def dashboard
    dashboards.first
  end
  #
  # Annotations
  #
  def step(step_name,&block)
    Log.notify "  * #{step_name}"
    yield if block
  end

  def test_name(test_name,&block)
    Log.notify test_name
    yield if block
  end
  #
  # Basic operations
  #
  attr_reader :result
  def on(host, command, options={}, &block)
    options[:acceptable_exit_codes] ||= [0]
    options[:failing_exit_codes]    ||= [1]
    if command.is_a? String
      command = Command.new(command)
    end
    if host.is_a? Array
      host.each { |h| on h, command, options, &block }
    else
      @result = command.exec(host, options)

      unless options[:silent] then
        result.log
        if options[:acceptable_exit_codes].include?(exit_code)
          # cool.
        elsif options[:failing_exit_codes].include?(exit_code)
          assert( false, "Exited with #{exit_code}" )
        else
          raise "Exited with #{exit_code}"
        end
      end

      # Also, let additional checking be performed by the caller.
      yield if block_given?

      return @result
    end
  end

  def scp_to(host,from_path,to_path,options={})
    if host.is_a? Array
      host.each { |h| scp_to h,from_path,to_path,options }
    else
      @result = host.do_scp(from_path, to_path)
      result.log
      raise "scp exited with #{result.exit_code}" if result.exit_code != 0
    end
  end

  def pass_test(msg)
    Log.notify msg
  end
  def fail_test(msg)
    assert(false, msg)
  end
  #
  # result access
  #
  def stdout
    result.stdout
  end
  def stderr
    result.stderr
  end
  def exit_code
    result.exit_code
  end
  #
  # Macros
  #

  def facter(*args)
    FacterCommand.new(*args)
  end

  def puppet_resource(*args)
    PuppetCommand.new(:resource,*args)
  end

  def puppet_doc(*args)
    PuppetCommand.new(:doc,*args)
  end

  def puppet_kick(*args)
    PuppetCommand.new(:kick,*args)
  end

  def puppet_cert(*args)
    PuppetCommand.new(:cert,*args)
  end

  def puppet_apply(*args)
    PuppetCommand.new(:apply,*args)
  end

  def puppet_master(*args)
    PuppetCommand.new(:master,*args)
  end

  def puppet_agent(*args)
    PuppetCommand.new(:agent,*args)
  end

  def apply_manifest_on(host,manifest,options={},&block)
    on_options = {:stdin => manifest + "\n"}
    on_options[:acceptable_exit_codes] = options.delete(:acceptable_exit_codes) if options.keys.include?(:acceptable_exit_codes)
    args = ["--verbose"]
    args << "--parseonly" if options[:parseonly]
    on host, puppet_apply(*args), on_options, &block
  end

  def run_agent_on(host,arg='--no-daemonize --verbose --onetime --test')
    if host.is_a? Array
      host.each { |h| run_agent_on h }
    elsif ["ticket #5541 is a pain and hasn't been fixed"] # XXX
      2.times { on host,puppet_agent(arg),:silent => true }
      result.log
      raise "Error code from puppet agent" if result.exit_code != 0
    else
      on host,puppet_agent(arg)
    end
  end

  def requires_at_least(n, role)
    raise TestNotApplicableError.new unless 
    (case(role)
       when *[:master, :masters]
         masters
       when *[:agent, :agents]
         agents
       when *[:dashboard, :dashboards]
         dashboards
     end.length >= n)
  end

  def requires(role)
    requires_at_least 1, role
  end

  def time_sync
    step "Sync time via ntpdate"
    on hosts,"ntpdate pool.ntp.org"
  end

  def clean_hosts
    step "Clean Hosts"
    on hosts,"rpm -qa | grep puppet | xargs rpm -e; rpm -qa | grep pe- | xargs rpm -e; rm -rf puppet-enterprise*; rm -rf /etc/puppetlabs"
  end
  def prep_initpp(host, entry, path="/etc/puppetlabs/puppet/modules/puppet_system_test/manifests")
    # Rewrite the init.pp file with an additional class to test
    # eg: class puppet_system_test {
    #  include group
    #  include user
    #}
    step "Append new system_test_class to init.pp"
    # on host,"cd #{path} && head -n -1 init.pp > tmp_init.pp && echo include #{entry} >> tmp_init.pp && echo \} >> tmp_init.pp && mv -f tmp_init.pp init.pp"
    on host,"cd #{path} && echo class puppet_system_test \{ > init.pp && echo include #{entry} >> init.pp && echo \} >>init.pp"
  end
end
