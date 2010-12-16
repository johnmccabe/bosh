require 'spec_helper'

describe Bosh::Cli::Runner do

  before(:all) do
    @out = StringIO.new
    Bosh::Cli::Config.output = @out
  end

  def test_cmd(args, namespace, action, cmd_args = [])
    runner = Bosh::Cli::Runner.new(args)
    runner.parse_command!
    runner.namespace.should == namespace
    runner.action.should    == action
    runner.cmd_args.should  == cmd_args
  end

  it "dispatches commands to appropriate methods" do
    test_cmd(["version"], :dashboard, :version)
    test_cmd(["status"], :dashboard, :status)    
    test_cmd(["target"], :dashboard, :show_target)
    test_cmd(["target", "test"], :dashboard, :set_target, ["test"])
    test_cmd(["deploy"], :deployment, :perform)
    test_cmd(["deployment"], :deployment, :show_current)
    test_cmd(["deployment", "test"], :deployment, :set_current, ["test"])
    test_cmd(["user", "create", "admin"], :user, :create, ["admin"])
    test_cmd(["user", "create", "admin", "12321"], :user, :create, ["admin", "12321"])
    test_cmd(["login", "admin", "12321"], :dashboard, :login, ["admin", "12321"])
    test_cmd(["logout"], :dashboard, :logout)
    test_cmd(["purge"], :dashboard, :purge_cache)
    test_cmd(["task", "500"], :task, :track, ["500"])
    test_cmd(["release", "upload", "/path"], :release, :upload, ["/path"])
    test_cmd(["release", "verify", "/path"], :release, :verify, ["/path"])
    test_cmd(["stemcell", "verify", "/path"], :stemcell, :verify, ["/path"])
    test_cmd(["stemcell", "upload", "/path"], :stemcell, :upload, ["/path"])    
  end

  it "sometimes ignores tail" do
    test_cmd(["deploy", "--mutator", "me", "heaven", "bzzz"], :deployment, :perform, [])
    test_cmd(["stemcell", "upload", "/path/to/file", "AAAA"], :stemcell, :upload, ["/path/to/file", "AAAA"])
  end

  it "ignores weirdness" do
    test_cmd(["blablabla", "--mutator", "/path/to/adsa"], nil, nil, nil)
  end
  
end
