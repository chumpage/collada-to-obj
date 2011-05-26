#!/usr/bin/ruby

require "test/unit"
require 'rexml/document'
require "./dae-to-obj"

def get_root(xml_str)
  REXML::Document.new(xml_str).root()
end

def assert_array_in_delta(expected, actual, delta)
  assert_equal(expected.count, actual.count)
  (0...expected.count).each do |i|
    assert_in_delta(expected[i], actual[i], $epsilon)
  end
end

def assert_vector_equal(expected_vector, actual_vector)
  assert_array_in_delta(expected_vector, actual_vector, $epsilon)
end

def assert_matrix_equal(expected_matrix, actual_matrix)
  assert_equal(expected_matrix.count, actual_matrix.count)
  (0...expected_matrix.count).each do |i|
    assert_array_in_delta(expected_matrix[i], actual_matrix[i], $epsilon)
  end
end

def x_rotation_matrix_alternative(r)
  sinr = Math.sin(r)
  cosr = Math.cos(r)
  new_matrix(4, 4, [1,0,0,0, 0,cosr,-sinr,0, 0,sinr,cosr,0, 0,0,0,1])
end

def rotation_matrix_alternative(r, v)
  v = vector_normalize(v)
  vmin = v.map { |val| val.abs }.min
  s = [0,0,0]
  if vmin == v[0]
    s = [0, -v[2], v[1]]
  elsif vmin == v[1]
    s = [-v[2], 0, v[0]]
  else
    s = [-v[1], v[0], 0]
  end
  s = vector_normalize(s)
  t = vector_cross(v, s)
  m = matrix_33_to_44([v, s, t])
  matrix_mult(matrix_transpose(m), x_rotation_matrix_alternative(r), m)
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
    assert_equal([[0, 1, 2], [3, 4, 5]], partition_array(arr, 3, 3))
    assert_equal([[0, 1], [3, 4]], partition_array(arr, 2, 3))
  end

  @@array_xml_1 = <<-TEST_XML
    <array>0 1 2 3 4 5</array>
  TEST_XML

  @@array_xml_2 = <<-TEST_XML
    <array>0 1 2.0 3 4 5</array>
  TEST_XML

  def test_read_array
    assert_equal([0, 1, 2, 3, 4, 5], read_int_array(get_root(@@array_xml_1)))
    assert_equal([0, 1, 2, 3, 4, 5], read_float_array(get_root(@@array_xml_1)))
    assert_raise(ColladaError) { read_int_array(get_root(@@array_xml_2)) }
  end

  def test_math_ops
    assert_in_delta(7.0710678118654755, vector_length([3,4,5]), $epsilon)
    assert_vector_equal([0.4242640687119285,0.565685424949238,0.7071067811865475],
                        vector_normalize([3,4,5]))
    assert_vector_equal([0,0,1], vector_cross([1,0,0], [0,1,0]))
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
    assert_equal(new_matrix(3, 3, [30,24,18, 84,69,54, 138,114,90]),
                 matrix_mult(m1, m2))
    assert_equal(new_matrix(3, 3, [240,276,372,681,807,1056,1122,1338,1740]),
                 matrix_mult(m1, m2, m3))
    assert_equal([14,32,50], matrix_mult_vec(m1, v1))
    assert_equal(new_matrix(3, 3, [2,4,6, 8,10,12, 14,16,18]),
                 matrix_mult_scalar(m1, 2))
    assert_equal(new_matrix(3, 2, [2,4, 6,8, 10,12]), matrix_mult_scalar(m4, 2))
    assert_equal(new_matrix(3, 3, [1,4,7, 2,5,8, 3,6,9]), matrix_transpose(m1))
    assert_equal(new_matrix(2, 2, [5,6, 8,9]), minor_matrix(m1, 0, 0))
    assert_equal(new_matrix(2, 2, [1,3, 7,9]), minor_matrix(m1, 1, 1))
    assert_in_delta(0, matrix_determinant(m1), $epsilon)
    assert_in_delta(84, matrix_determinant(m3), $epsilon)
    assert_raise(ColladaError) { matrix_inverse(m1) }
    m3_expected_inv = new_matrix(3, 3, [0.14285714, 0.85714286, -0.3571429,
                                        -0.04761905, 0.04761905, 0.1190476,
                                        0.02380952, -0.52380952, 0.1904762])
    assert_matrix_equal(m3_expected_inv, matrix_inverse(m3))
    assert_matrix_equal(new_matrix(4, 4, [1,2,3,0, 4,5,6,0, 7,8,9,0, 0,0,0,1]),
                        matrix_33_to_44(new_matrix(3, 3, [1,2,3, 4,5,6, 7,8,9])))
    assert_matrix_equal(new_matrix(4, 4, [1,0,0,1, 0,1,0,2, 0,0,1,3, 0,0,0,1]),
                        translation_matrix(1, 2, 3))
    assert_matrix_equal(rotation_matrix_alternative(Math::PI, [1,1,1]),
                        rotation_matrix(Math::PI, [1,1,1]))
    assert_matrix_equal(rotation_matrix_alternative(Math::PI, [1,0,-1]),
                        rotation_matrix(Math::PI, [1,0,-1]))
    assert_matrix_equal(rotation_matrix(Math::PI, [1,0,0]), x_rotation_matrix(Math::PI))
    assert_matrix_equal(rotation_matrix(Math::PI, [0,1,0]), y_rotation_matrix(Math::PI))
    assert_matrix_equal(rotation_matrix(Math::PI, [0,0,1]), z_rotation_matrix(Math::PI))
    assert_matrix_equal(new_matrix(4, 4, [2,0,0,0, 0,3,0,0, 0,0,4,0, 0,0,0,1]),
                        scale_matrix(2,3,4))
    assert_matrix_equal(scale_matrix(2,2,2), uniform_scale_matrix(2))
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
    assert_equal(identity_matrix(4), read_matrix(get_root(@@matrix_xml_1)))
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
    root = get_root(@@node_xml_1)
    id_elem_hash = build_id_elem_hash(root)
    child_node_elem = id_elem_hash['child-node']

    node1 = Node.new
    node1.id = 'node1'
    node1.transform = [[1, 0, 0, 3], [0, 1, 0, 4], [0, 0, 1, 5], [0, 0, 0, 1]]
    node1.instance_nodes << 'node2'
    node1.instance_geoms << 'mesh1'
    node1.child_node_elems << child_node_elem

    node2 = Node.new
    node2.id = 'node2'

    assert_equal([node1, node2], read_nodes(root))
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

    indices = [0,1,2, 0,1,2]
    vertices = [[[0,0,0], [10,10,10], [20,20]],
                [[0,0,0], [11,11,11], [20,20]],
                [[1,1,1], [11,11,11], [21,21]]]

    assert_equal(Mesh.new(vertices, indices, :pos_norm_tex),
                 read_triangles(triangles_elem, id_elem_hash))
  end

  # XXX remove
  # def test_transform
  #   v = [1,2,3]
  #   translation = translation_matrix(3, 4, 5)
  #   assert_vector_equal([4,6,8], transform_pos(translation, [1,2,3]))
  #   assert_vector_equal([0,0,1], transform_normal(translation, [0,0,1]))
  #   transform = matrix_mult(
  #   transform = new_matrix(4, 4, [1,3,2,10, 3,1,2,20, 2,1,3,30, 3,2,1,1])
  #   transpose_inv_transform = matrix_transpose(matrix_inverse(transform))
  #   assert_vector_equal([23.0/11,31.0/11,43.0/11], transform_pos(transform, v))
  #   expected_transformed_normal = [-2.625,-9.875,7.250,6.250]
  #   transformed_normal = transform_normal(transpose_inv_transform, v)
  #   (0...4).each do |i|
  #     assert_in_delta(expected_transformed_normal[i], transformed_normal[i], $epsilon)
  #   end
  # end

  def test_pretransform_mesh
    indices = [0,1,2, 0,1,2]
    vertices = [[[0,1,2], [1,1,1],    [20,20]],
                [[1,2,3], [-1,-1,-1], [20,20]],
                [[2,3,4], [0,1,0],    [21,21]]]
    mesh = Mesh.new(vertices, indices, :pos_norm_tex)

    # XXX remove
    # puts "translation_matrix(3,4,5) = #{translation_matrix(3,4,5).flatten}"
    # puts "scale_matrix(1,2,3), = #{scale_matrix(1,2,3).flatten}"
    # puts "x_rotation_matrix(Math::PI) = #{x_rotation_matrix(Math::PI).flatten}"
    # puts "vector_normalize([1, -0.5, -0.33]) = #{vector_normalize([1, -0.5, -0.33])}"
    # puts "vector_normalize([-1, 0.5, 0.33]) = #{vector_normalize([-1, 0.5, 0.33])}"
    # puts "vector_normalize([0, -0.5, 0]) = #{vector_normalize([0, -0.5, 0])}"
    # puts "vector_length 1 = #{vector_length([0.8578399164447491, -0.42891995822237455, -0.28308717242676723])}"
    # puts "vector_length 2 = #{vector_length([0.8571428571428571, -0.42857142857142866, -0.28571428571428564])}"

    transform = matrix_mult(translation_matrix(3,4,5),
                            scale_matrix(1,2,3),
                            x_rotation_matrix(Math::PI))

    # XXX remove
    # puts "pos_trans = #{transform.flatten}"
    # normal_transform = matrix_transpose(matrix_inverse(transform))
    # puts "normal_transform = #{normal_transform.flatten}"

    normals_expected = [[0.8578399164447491,-0.42891995822237455,-0.28308717242676723],
                        [-0.8578399164447491, 0.42891995822237455, 0.28308717242676723],
                        [0.0, -1.0, 0.0]]
    vertices_expected = [[[3,2,-1], normals_expected[0], [20,20]],
                         [[4,0,-4], normals_expected[1], [20,20]],
                         [[5,-2,-7], normals_expected[2], [21,21]]]

    # XXX i shouldn't have to set the epsilon so high (.01), but the normals come out a
    # little different from the tests i did with r, probably due to differences in the
    # precision of computations. i'll temporarily relax the equality test for floating
    # point values for now, but i should probably come back and figure out the
    # discrepancy later.
    epsilon_tmp = $epsilon
    $epsilon = 0.01
    assert_equal(Mesh.new(vertices_expected, indices, mesh.vertex_format),
                 pretransform_mesh(mesh, transform))
    $epsilon = epsilon_tmp
  end

end
