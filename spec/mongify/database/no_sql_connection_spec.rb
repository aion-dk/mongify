require 'spec_helper'

describe Mongify::Database::NoSqlConnection do
  before(:each) do
    @host = '127.0.0.1'
    @database = 'mongify_test'
    @mongodb_connection = Mongify::Database::NoSqlConnection.new
  end
  
  context "valid?" do
    it "should be true" do
      Mongify::Database::NoSqlConnection.new(:host => 'localhost', :database => 'blue').should be_valid
    end
    it "should be false without any params" do
      Mongify::Database::NoSqlConnection.new().should_not be_valid
    end
    
    it "should be false without database" do
      Mongify::Database::NoSqlConnection.new(:host => 'localhost').should_not be_valid
    end
    
    it "should be false without host" do
      Mongify::Database::NoSqlConnection.new(:database => 'blue').should_not be_valid
    end
  end
  
  context "connection string" do
    before(:each) do
      @mongodb_connection.host @host
      @mongodb_connection.database @database
    end
    
    context "without username or password" do
      it "should render correctly" do
        @mongodb_connection.connection_string.should == "mongodb://#{@host}"
      end
      
      it "should include port" do
        @mongodb_connection.port 10101
        @mongodb_connection.connection_string.should == "mongodb://#{@host}:10101"
      end
    end
  end
  
  context "connection" do
    before(:each) do
      @mock_connection = mock(:connected? => true)
      Mongo::Connection.stub(:new).and_return(@mock_connection)
    end
    
    it "should only create a connection once" do
      Mongo::Connection.should_receive(:new).once
      @mongodb_connection.connection
      @mongodb_connection.connection
    end
    
    it "should add_auth if username && password is present" do
      @mock_connection.should_receive(:add_auth)
      @mongodb_connection.username "bob"
      @mongodb_connection.password "secret"
      @mongodb_connection.connection
    end
    
    it "should reset connection on reset" do
      Mongo::Connection.should_receive(:new).twice
      @mongodb_connection.connection
      @mongodb_connection.reset!
      @mongodb_connection.connection
    end
  end
  
  describe "working connection" do
    before(:each) do
      @mongodb_connection = GenerateDatabase.mongo_connection
    end
    
    it "should work" do
      @mongodb_connection.should be_valid
      @mongodb_connection.should have_connection
    end
    
    it "should return a db" do
      @mongodb_connection.db.should be_a Mongify::Database::NoSqlConnection::DB
    end
  end
  
end
