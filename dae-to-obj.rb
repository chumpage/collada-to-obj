#!/usr/bin/ruby
require 'rexml/document'

class ColladaError < StandardError  
end

def to_int(str)
  Integer(str) rescue raise ColladaError.new("#{str} isn't a valid integer")
end

def to_float(str)
  Float(str) rescue raise ColladaError.new("#{str} isn't a valid float")
end

def partition_array(array, sub_array_length, stride)
  if stride < sub_array_length
    raise ColladaError.new("partition_array error: stride (#{stride}) < sub_array_length #{sub_array_length}")
  end
  if array.count % stride != 0
    raise ColladaError.new("partition_array error: array.count (#{array.count}) % stride #{stride} != 0")
  end
  sub_arrays = []
  0.step(array.count-1, stride) do |i|
    sub_arrays << array[i, sub_array_length]
  end
  sub_arrays
end

def read_numeric_array(elem, conversion_fn)
  elem.text.to_s.split.map {|str_val| send(conversion_fn, str_val)}
end

def read_int_array(elem)
  read_numeric_array(elem, :to_int)
end

def read_float_array(elem)
  read_numeric_array(elem, :to_float)
end

class Node
  attr_accessor :id, :transform, :child_nodes, :instance_nodes, :instance_geoms

  def initialize
    @id = ""
    @transform = nil
    @child_nodes = []
    @instance_nodes = []
    @instance_geoms = []
  end

  def ==(node)
    @id == node.id and
      @transform == node.transform and
      @child_nodes == node.child_nodes and
      @instance_nodes == node.instance_nodes and
      @instance_geoms == node.instance_geoms
  end
end

def build_id_elem_hash(root)
  table = root.attributes['id'] ? {root.attributes['id'] => root} : {}
  root.each_recursive do |elem|
    if elem.attributes['id'] != nil
      table[elem.attributes['id']] = elem
    end
  end
  table
end

def get_attr_str(elem, attr_name)
  val = elem.attributes[attr_name]
  if val == nil
    raise ColladaError.new("<#{elem.name}> element missing '#{attr_name}' attr")
  end
  val
end

def get_attr_int(elem, attr_name)
  to_int(get_attr_str(elem, attr_name))
end

def read_url(elem, attr_name)
  url = elem.attributes[attr_name]
  if url == nil or url.empty? or url[0] != "#" or url.length == 1
    raise ColladaError.new("missing or incorrectly formatted '#{attr_name}' attribute")
    nil
  else
    url[1..-1]
  end
end

def id_to_elem(id, id_elem_hash)
  elem = id_elem_hash[id]
  if elem == nil
    raise ColladaError.new("couldn't find element with id=#{id}")
  end
  elem
end

def elem_url_ref_to_elem(elem, attr_name, id_elem_hash)
  url_ref = read_url(elem, attr_name)
  id_to_elem(url_ref, id_elem_hash)
end

def get_child_elem(elem, child_name)
  child_elem = elem.elements[child_name]
  if child_elem == nil
    raise ColladaError.new("couldn't find <#{child_name}> child of <#{elem.name}> element")
  end
  child_elem
end

def read_matrix(matrix_elem)
  array = read_float_array(matrix_elem)
  if array.count != 16
    raise ColladaError.new("incorrectly formatted <matrix> element")
  end
  [array[0...4], array[4...8], array[8...12], array[12...16]]
end

def read_node(node_elem)
  node = Node.new
  id = node_elem.attributes['id']
  if id != nil
    node.id = id
  end
  node_elem.elements.each('node') do |child_node_elem|
    node.child_nodes << read_node(child_node_elem)
  end
  node_elem.elements.each('instance_node') do |instance_node_elem|
    url = read_url(instance_node_elem, 'url')
    node.instance_nodes << url if url != nil
  end
  node_elem.elements.each('instance_geometry') do |instance_geom_elem|
    url = read_url(instance_geom_elem, 'url')
    node.instance_geoms << url if url != nil
  end
  if node_elem.get_elements('matrix').count > 1
    raise ColladaError.new("more than one <matrix> element in a node. unsupported for now.")
  end
  matrix_elem = node_elem.elements['matrix']
  node.transform = read_matrix(matrix_elem) if matrix_elem != nil
  node
end

# returns a list of Nodes
def read_nodes(elem)
  return [] if elem == nil
  nodes = []
  elem.elements.each('node') do |node_elem|
    nodes << read_node(node_elem)
  end
  nodes
end

class Mesh
  # valid vertex formats
  #   - :pos
  #   - :pos_norm
  #   - :pos_tex
  #   - :pos_norm_tex

  attr_accessor :vertex_format, :vertices, :indices

  def initialize(vertices, indices, vertex_format)
    @vertices = vertices
    @indices = indices
    @vertex_format = vertex_format
  end

  def ==(mesh)
    @vertex_format == mesh.vertex_format and
      @vertices == mesh.vertices and
      @indices == mesh.indices
  end
end

def get_vertex_format(has_normals, has_texcoords)
  case [!!has_normals, !!has_texcoords]
  when [false, false]
    :pos
  when [true, false]
    :pos_norm
  when [false, true]
    :pos_tex
  when [true, true]
    :pos_norm_tex
  end
end

# returns a hash
#   {:vertex => {:source => "source_url", :offset => <int>},
#    :normal => ...,
#    :texcoord => ...}
def read_triangles_inputs(triangles_elem)
  inputs = {}
  triangles_elem.elements.each('input') do |input_elem|
    semantic = get_attr_str(input_elem, 'semantic')
    source = read_url(input_elem, 'source')
    offset = get_attr_int(input_elem, 'offset')
    set_str = input_elem.attributes['set']
    set = set_str == nil ? 0 : to_int(set_str)

    hash_val = {:source => source, :offset => offset}
    inputs[:vertex] = hash_val if semantic.upcase == "VERTEX" and inputs[:vertex] == nil
    inputs[:normal] = hash_val if semantic.upcase == "NORMAL" and inputs[:normal] == nil
    inputs[:texcoord] = hash_val if semantic.upcase == "TEXCOORD" and set == 0 and inputs[:texcoord] == nil
  end
  raise ColladaError.new("missing <input> with semantic=VERTEX") if inputs[:vertex] == nil
  inputs
end

# returns the url of the position <source>
def get_vertices_position_source(vertices_id, id_elem_hash)
  vertices_elem = id_to_elem(vertices_id, id_elem_hash)
  vertices_elem.elements.each('input') do |input_elem|
    semantic = get_attr_str(input_elem, 'semantic')
    if semantic.upcase == "POSITION"
      return read_url(input_elem, 'source')
    end
  end
  raise ColladaError.new("couldn't read <input> with semantic=POSITION from <vertices>")
end

def get_triangles_index_stride(triangles_elem)
  max_offset = -1
  triangles_elem.elements.each('input') do |input_elem|
    offset_str = input_elem.attributes['offset']
    if offset_str
      offset = to_int(offset_str)
      max_offset = [max_offset, offset].max
    end
  end
  max_offset + 1
end

# returns an array of arrays, where each sub-array is a position, normal, or tex coord
def read_source(source_id, id_elem_hash, *expected_param_names)
  source_elem = id_to_elem(source_id, id_elem_hash)
  technique_common_elem = get_child_elem(source_elem, 'technique_common')
  accessor_elem = get_child_elem(technique_common_elem, 'accessor')
  param_names = []
  accessor_elem.elements.each('param') do |param_elem|
    param_name = get_attr_str(param_elem, 'name')
    param_type = get_attr_str(param_elem, 'type')
    if param_type != "float"
      raise ColladaError.new("<param>s with type=#{param_type} are not supported")
    end
    param_names << param_name.upcase
  end
  expected_param_names = expected_param_names.map {|name| name.upcase}
  if expected_param_names != param_names
    raise ColladaError.new("got unexpected params #{param_names} in <accessor>. expected #{expected_param_names}.")
  end

  accessor_count = get_attr_int(accessor_elem, 'count')
  accessor_stride = get_attr_int(accessor_elem, 'stride')
  if param_names.count != accessor_stride
    raise ColladaError.new("number of <param>s should match <accessor> stride value")
  end

  array_elem = elem_url_ref_to_elem(accessor_elem, 'source', id_elem_hash)
  array_count = get_attr_int(array_elem, 'count')
  if array_count != accessor_count*accessor_stride
    raise ColladaError.new("<float_array> and <accessor> counts don't match")
  end

  array_vals = read_float_array(array_elem)
  if array_vals.count != array_count
    raise ColladaError.new("actual number of vals in <float_array> doesn't match count attribute")
  end
  if array_vals.count%accessor_stride != 0
    raise ColladaError.new("internal error")
  end

  partition_array(array_vals, param_names.count, accessor_stride)
end

def sort_non_unified_index(non_unified_index, inputs)
  sorted_non_unified_index = [non_unified_index[inputs[:position][:offset]]]
  if inputs[:normal]
    sorted_non_unified_index << non_unified_index[inputs[:normal][:offset]]
  end
  if inputs[:texcoord]
    sorted_non_unified_index << non_unified_index[inputs[:texcoord][:offset]]
  end
  sorted_non_unified_index
end

# non_unified_indices input is [[ip0, in0, iuv0], [ip1, in1, iuv1], ...]
# output is [indices, vertices]
# indices = [i0, i1, i2, ...] <--- three integers == one triangle
# vertices = [[[px, py, pz], [nx, ny, nz], [u, v]], ...]
# note that the normals and tex coords are optional. they'll be in the output only if
# they're supplied in the input.
def convert_to_unified_indices(non_unified_indices, positions, normals, texcoords)
  indices = []
  vertices = []
  index_hash = {}

  non_unified_indices.each do |non_unified_index|
    if index_hash[non_unified_index] != nil
      indices << index_hash[non_unified_index]
    else
      new_index = indices.count
      indices << new_index
      index_hash[non_unified_index] = new_index
      vertex = [positions[non_unified_index[0]]]
      if normals
        vertex << normals[non_unified_index[1]]
      end
      if texcoords
        vertex << texcoords[non_unified_index[normals ? 2 : 1]]
      end
      vertices << vertex
    end
  end

  [indices, vertices]
end

# returns a Mesh
def read_triangles(triangles_elem, id_elem_hash)
  inputs = read_triangles_inputs(triangles_elem)
  position_source = get_vertices_position_source(inputs[:vertex][:source], id_elem_hash)
  inputs[:position] = inputs[:vertex].clone
  inputs[:position][:source] = position_source

  positions = read_source(inputs[:position][:source], id_elem_hash, 'X', 'Y', 'Z')
  normals = inputs[:normal] ? read_source(inputs[:normal][:source], id_elem_hash, 'X', 'Y', 'Z') : nil
  texcoords = inputs[:texcoord] ? read_source(inputs[:texcoord][:source], id_elem_hash, 'S', 'T') : nil

  index_stride = get_triangles_index_stride(triangles_elem)
  p_elem = get_child_elem(triangles_elem, 'p')

  indices = partition_array(read_int_array(p_elem), index_stride, index_stride)
  indices = indices.map { |non_unified_index| sort_non_unified_index(non_unified_index, inputs) }
  indices, vertices = convert_to_unified_indices(indices, positions, normals, texcoords)

  Mesh.new(vertices, indices, get_vertex_format(!!normals, !!texcoords))
end

# returns a Mesh array
def read_geometry(geom_elem, id_elem_hash)
  mesh_elem = get_child_elem(geom_elem, 'mesh')
  meshes = []
  mesh_elem.elements.each('triangles') do |triangles_elem|
    meshes << read_triangles(triangles_elem, id_elem_hash)
  end
  meshes
end

# main
if $0 == __FILE__
  # doc = REXML::Document.new(File.open('/st/misc/model.dae'))
  # id_elem_hash = build_id_elem_hash(doc.root)
  # scene_nodes = read_nodes(doc.elements['/COLLADA/library_visual_scenes/visual_scene'], id_elem_hash)
  puts 'kaka'
end
