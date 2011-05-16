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

  @@url_xml_1 = <<-TEST_XML
    <input semantic="VERTEX" source="#mesh1-geometry-vertex" offset="0"/>
  TEST_XML
  
  @@url_xml_2 = <<-TEST_XML
    <input semantic="VERTEX" offset="0"/>
  TEST_XML
  
  @@url_xml_3 = <<-TEST_XML
    <input semantic="VERTEX" source="" offset="0"/>
  TEST_XML
  
  @@url_xml_4 = <<-TEST_XML
    <input semantic="VERTEX" source="#" offset="0"/>
  TEST_XML
  
  @@url_xml_5 = <<-TEST_XML
    <input semantic="VERTEX" source="blah#hey" offset="0"/>
  TEST_XML
  
  def test_read_url
    assert_equal(read_url(get_root(@@url_xml_1), "source"), "mesh1-geometry-vertex")
    assert_raise(ColladaError) { read_url(get_root(@@url_xml_2), "source") }
    assert_raise(ColladaError) { read_url(get_root(@@url_xml_3), "source") }
    assert_raise(ColladaError) { read_url(get_root(@@url_xml_4), "source") }
    assert_raise(ColladaError) { read_url(get_root(@@url_xml_5), "source") }
  end

  @@matrix_xml_1 = <<-TEST_XML
    <matrix>1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</matrix>
  TEST_XML

  @@matrix_xml_2 = <<-TEST_XML
    <matrix>1 0 0 0 0 1 0 0 0 0 1 0 0 0 0</matrix>
  TEST_XML

  @@matrix_xml_3 = <<-TEST_XML
    <matrix>1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0</matrix>
  TEST_XML

  @@matrix_xml_4 = <<-TEST_XML
    <matrix>1 0 0 0 0 1 0 0 0 0 1 0 blah 0 0 1</matrix>
  TEST_XML

  def test_read_matrix
    assert_equal(read_matrix(get_root(@@matrix_xml_1)), [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
    assert_raise(ColladaError) { read_matrix(get_root(@@matrix_xml_2)) }
    assert_raise(ColladaError) { read_matrix(get_root(@@matrix_xml_3)) }
    assert_raise(ColladaError) { read_matrix(get_root(@@matrix_xml_4)) }
  end

  @@node_xml_1 = <<-TEST_XML
    <visual_scene>
      <node id="node1" name="my-node">
        <matrix>1 0 0 3 0 1 0 4 0 0 1 5 0 0 0 1</matrix>
        <instance_node url="#node2"/>
        <instance_geometry url="#mesh1"/>
        <node id="child-node">
          <instance_node url="#node2"/>
        </node>
      </node>
      <node id="node2"/>
    </visual_scene>
  TEST_XML

  def test_read_node
    child_node = Node.new
    child_node.id = 'child-node'
    child_node.instance_nodes << 'node2'

    node1 = Node.new
    node1.id = 'node1'
    node1.transform = [[1, 0, 0, 3], [0, 1, 0, 4], [0, 0, 1, 5], [0, 0, 0, 1]]
    node1.instance_nodes << 'node2'
    node1.instance_geoms << 'mesh1'
    node1.child_nodes << child_node

    node2 = Node.new
    node2.id = 'node2'

    root = get_root(@@node_xml_1)
    assert_equal([node1, node2], read_nodes(root, build_id_table(root)))
  end

  @@inputs_xml_1 = <<-TEST_XML
    <triangles material="material" count="2">
      <input semantic="VERTEX" source="#mesh1-vertex" offset="0"/>
      <input semantic="NORMAL" source="#mesh1-normal" offset="1"/>
      <input semantic="TEXCOORD" source="#mesh1-uv" offset="2" set="0"/>
      <p>0 0 0 1 0 1</p>
    </triangles>
  TEST_XML

end
