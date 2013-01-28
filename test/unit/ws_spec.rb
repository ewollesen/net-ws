# -*- coding: utf-8 -*-
require File.expand_path("../test_helper", File.dirname(__FILE__))
require "open3"


describe Net::WS do

  def with_echo_server(&block)
    echo_server_path = File.expand_path("../support/echo_server.py",
                                        File.dirname(__FILE__))

    Open3.popen3(echo_server_path) do |stdin, stdout, stderr|
      stdout.readline # the readline tells us the server is up
      yield "localhost", 9001
    end
  end

  it "should be sane" do
    true.must_equal true
  end

  it "can send and receive message" do
    msg = "foo"

    with_echo_server do |host, port|
      @ws = Net::WS.new("ws://#{host}:#{port}")

      @ws.open("/")
      @ws.send_text(msg)
      @ws.receive_message.must_equal(msg)
      @ws.close
    end
  end

  it "can send and receive a UTF-8 message" do
    msg = "∆AIMON"

    host = "localhost"; port = 9001
    with_echo_server do |host, port|
      @ws = Net::WS.new("ws://#{host}:#{port}")

      @ws.open("/")
      @ws.send_text(msg)
      @ws.receive_message.must_equal(msg)
      @ws.close
    end
  end

end
