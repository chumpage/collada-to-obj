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

  def test_partition_array
    arr = [0, 1, 2, 3, 4, 5]
    assert_equal(partition_array(arr, 3, 3), [[0, 1, 2], [3, 4, 5]])
    assert_equal(partition_array(arr, 2, 3), [[0, 1], [3, 4]])
  end

  @@array_xml_1 = <<-TEST_XML
    <array>0 1 2 3 4 5</array>
  TEST_XML

  @@array_xml_2 = <<-TEST_XML
    <array>0 1 2.0 3 4 5</array>
  TEST_XML

  def test_read_array
    assert_equal(read_int_array(get_root(@@array_xml_1)), [0, 1, 2, 3, 4, 5])
    assert_equal(read_float_array(get_root(@@array_xml_1)), [0, 1, 2, 3, 4, 5])
    assert_raise(ColladaError) { read_int_array(get_root(@@array_xml_2)) }
  end

  def test_matrix_ops
    epsilon = 1e-6
    m1 = new_matrix(3, 3, [1,2,3, 4,5,6, 7,8,9])
    m2 = new_matrix(3, 3, [9,8,7, 6,5,4, 3,2,1])
    m3 = new_matrix(3, 3, [6,2,10, 1,3,0, 2,8,4])
    m4 = new_matrix(3, 2, [1,2, 3,4, 5,6])
    v1 = [1,2,3]
    assert_equal([[0,0], [0,0], [0,0]], new_matrix(3, 2))
    assert_equal([[0], [0], [0], [0]], new_matrix(4, 1))
    assert_equal([[0,0,0,0]], new_matrix(1, 4))
    assert_equal([[0,1], [2,3]], new_matrix(2, 2, [0,1, 2,3]))
    assert_equal(new_matrix(3, 3, [1,0,0, 0,1,0, 0,0,1]), identity_matrix(3))
    assert_equal([3, 3], matrix_dimensions(identity_matrix(3)))
    assert_equal(new_matrix(3, 3, [30,24,18, 84,69,54, 138,114,90]), matrix_mult(m1, m2))
    assert_equal([14,32,50], matrix_mult_vec(m1, v1))
    assert_equal(new_matrix(3, 3, [2,4,6, 8,10,12, 14,16,18]), matrix_mult_scalar(m1, 2))
    assert_equal(new_matrix(3, 2, [2,4, 6,8, 10,12]), matrix_mult_scalar(m4, 2))
    assert_equal(new_matrix(3, 3, [1,4,7, 2,5,8, 3,6,9]), matrix_transpose(m1))
    assert_equal(new_matrix(2, 2, [5,6, 8,9]), minor_matrix(m1, 0, 0))
    assert_equal(new_matrix(2, 2, [1,3, 7,9]), minor_matrix(m1, 1, 1))
    assert_in_delta(0, matrix_determinant(m1), epsilon)
    assert_in_delta(84, matrix_determinant(m3), epsilon)
    assert_raise(ColladaError) { matrix_inverse(m1) }
    m3_inv = matrix_inverse(m3).flatten()
    m3_expected_inv = [0.14285714, 0.85714286, -0.3571429, -0.04761905, 0.04761905, 0.1190476, 0.02380952, -0.52380952, 0.1904762]
    (0...matrix_element_count(m3)).each do |i|
      assert_in_delta(m3_expected_inv[i], m3_inv[i], epsilon)
    end
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

    assert_equal([node1, node2], read_nodes(get_root(@@node_xml_1)))
  end

  @@triangles_inputs_xml_1 = <<-TEST_XML
    <triangles material="material" count="2">
      <input semantic="VERTEX" source="#mesh1-vertex" offset="0"/>
      <input semantic="NORMAL" source="#mesh1-normal" offset="1"/>
      <input semantic="TEXCOORD" source="#mesh1-uv" offset="2" set="0"/>
      <p>0 0 0 1 0 1</p>
    </triangles>
  TEST_XML

  def test_read_triangles_inputs
    expected = {:vertex => {:source => 'mesh1-vertex', :offset => 0},
      :normal => {:source => 'mesh1-normal', :offset => 1},
      :texcoord => {:source => 'mesh1-uv', :offset => 2}}
    assert_equal(expected, read_triangles_inputs(get_root(@@triangles_inputs_xml_1)))
  end

  @@position_source_xml_1 = <<-TEST_XML
    <mesh>
      <source id="mesh1-position"/>
      <vertices id="mesh1-vertex">
        <input semantic="POSITION" source="#mesh1-position"/>
      </vertices>
    </mesh>
  TEST_XML

  def test_get_vertices_position_source
    root = get_root(@@position_source_xml_1)
    assert_equal('mesh1-position', get_vertices_position_source('mesh1-vertex', build_id_elem_hash(root)))
  end

  @@index_stride_xml_1 = <<-TEST_XML
    <triangles material="material" count="2">
      <input semantic="VERTEX" source="#mesh1-vertex" offset="0"/>
      <input semantic="NORMAL" source="#mesh1-normal" offset="1"/>
      <input semantic="TEXCOORD" source="#mesh1-uv" offset="2" set="0"/>
      <p>0 0 0 1 0 1</p>
    </triangles>
  TEST_XML

  def test_get_triangles_index_stride
    assert_equal(3, get_triangles_index_stride(get_root(@@index_stride_xml_1)))
  end

  @@source_xml_1 = <<-TEST_XML
    <source id="mesh-position">
      <float_array id="mesh-position-array" count="6">0 1 2 3 4 5</float_array>
      <technique_common>
         <accessor source="#mesh-position-array" count="2" stride="3">
            <param name="X" type="float"/>
            <param name="Y" type="float"/>
            <param name="Z" type="float"/>
         </accessor>
      </technique_common>
    </source>
  TEST_XML

  def test_read_source
    root = get_root(@@source_xml_1)
    assert_equal([[0, 1, 2], [3, 4, 5]], read_source('mesh-position', build_id_elem_hash(root), 'X', 'Y', 'Z'))
  end

  def test_sort_non_unified_index
    inputs = {:position => {:offset => 0}, :normal => {:offset => 1}, :texcoord => {:offset => 2}}
    index = [0, 10, 20]
    assert_equal([0, 10, 20], sort_non_unified_index(index, inputs))
    inputs = {:position => {:offset => 3}, :normal => {:offset => 2}, :texcoord => {:offset => 0}}
    index = [20, 100, 10, 0]
    assert_equal([0, 10, 20], sort_non_unified_index(index, inputs))
  end

  def test_convert_to_unified_indices
    non_unified_indices = [[0, 0, 0], [0, 1, 0], [1, 1, 1], [0, 1, 0]]
    positions = [[0, 0, 0], [1, 1, 1]]
    normals = [[10, 10, 10], [11, 11, 11]]
    texcoords = [[20, 20], [21, 21]]
    unified_indices = [0, 1, 2, 1]
    vertices = [[[0, 0, 0], [10, 10, 10], [20, 20]],
                [[0, 0, 0], [11, 11, 11], [20, 20]],
                [[1, 1, 1], [11, 11, 11], [21, 21]]]
    assert_equal([unified_indices, vertices],
                 convert_to_unified_indices(non_unified_indices, positions, normals, texcoords))
  end

  @@triangles_xml_1 = <<-TEST_XML
    <mesh>
      <source id="mesh-position">
         <float_array id="mesh-position-array" count="6">0 0 0 1 1 1</float_array>
         <technique_common>
            <accessor source="#mesh-position-array" count="2" stride="3">
               <param name="X" type="float"/>
               <param name="Y" type="float"/>
               <param name="Z" type="float"/>
            </accessor>
         </technique_common>
      </source>
      <source id="mesh-normal">
         <float_array id="mesh-normal-array" count="6">10 10 10 11 11 11</float_array>
         <technique_common>
            <accessor source="#mesh-normal-array" count="2" stride="3">
               <param name="X" type="float"/>
               <param name="Y" type="float"/>
               <param name="Z" type="float"/>
            </accessor>
         </technique_common>
      </source>
      <source id="mesh-uv">
         <float_array id="mesh-uv-array" count="4">20 20 21 21</float_array>
         <technique_common>
            <accessor source="#mesh-uv-array" count="2" stride="2">
               <param name="S" type="float"/>
               <param name="T" type="float"/>
            </accessor>
         </technique_common>
      </source>
      <vertices id="mesh-vertex">
         <input semantic="POSITION" source="#mesh-position"/>
      </vertices>
      <triangles material="some-material" count="2">
         <input semantic="VERTEX" source="#mesh-vertex" offset="0"/>
         <input semantic="NORMAL" source="#mesh-normal" offset="1"/>
         <input semantic="TEXCOORD" source="#mesh-uv" offset="2" set="0"/>
         <p>0 0 0  0 1 0  1 1 1    0 0 0  0 1 0  1 1 1</p>
      </triangles>
    </mesh>
  TEST_XML

  def test_read_triangles
    root = get_root(@@triangles_xml_1)
    triangles_elem = get_child_elem(root, 'triangles')
    id_elem_hash = build_id_elem_hash(root)

    indices = [0, 1, 2, 0, 1, 2]
    vertices = [[[0, 0, 0], [10, 10, 10], [20, 20]],
                [[0, 0, 0], [11, 11, 11], [20, 20]],
                [[1, 1, 1], [11, 11, 11], [21, 21]]]

    assert_equal(Mesh.new(vertices, indices, :pos_norm_tex),
                 read_triangles(triangles_elem, id_elem_hash))
  end
end
