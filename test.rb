#!/usr/bin/ruby

require "test/unit"
require 'rexml/document'
require "./dae-to-obj"

def get_root(xml_str)
  REXML::Document.new(xml_str).root()
end

class TestDaeToObj < Test::Unit::TestCase
  def test_to_int
    assert_equal(3, to_int("3"))
    assert_raise(ColladaError) { to_int("blah") }
    assert_raise(ColladaError) { to_int("5 blah") }
    assert_raise(ColladaError) { to_int("3.2") }
  end

  def test_to_float
    assert_equal(3.0, to_float("3.0"))
    assert_equal(3.0, to_float("3"))
    assert_raise(ColladaError) { to_float("blah") }
    assert_raise(ColladaError) { to_float("5 blah") }
  end

  @@read_url_xml_1 = <<-TEST_XML
    <input semantic="VERTEX" source="#mesh1-geometry-vertex" offset="0"/>
  TEST_XML
  
  @@read_url_xml_2 = <<-TEST_XML
    <input semantic="VERTEX" offset="0"/>
  TEST_XML
  
  @@read_url_xml_3 = <<-TEST_XML
    <input semantic="VERTEX" source="" offset="0"/>
  TEST_XML
  
  @@read_url_xml_4 = <<-TEST_XML
    <input semantic="VERTEX" source="#" offset="0"/>
  TEST_XML
  
  @@read_url_xml_5 = <<-TEST_XML
    <input semantic="VERTEX" source="blah#hey" offset="0"/>
  TEST_XML
  
  def test_read_url
    assert_equal(read_url(get_root(@@read_url_xml_1), "source"), "mesh1-geometry-vertex")
    assert_raise(ColladaError) { read_url(get_root(@@read_url_xml_2), "source") }
    assert_raise(ColladaError) { read_url(get_root(@@read_url_xml_3), "source") }
    assert_raise(ColladaError) { read_url(get_root(@@read_url_xml_4), "source") }
    assert_raise(ColladaError) { read_url(get_root(@@read_url_xml_5), "source") }
  end
end
