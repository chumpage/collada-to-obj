#!/usr/bin/ruby1.9.1
require 'rexml/document'

class Node
  attr_accessor :id, :transform, :child_nodes, :instance_nodes, :instance_geoms

  def initialize
    @id = ""
    @transform = nil
    @child_nodes = []
    @instance_nodes = []
    @instance_geoms = []
  end
end

class ElementData
  attr_accessor :xml_elem, :internal_instance

  def initialize(elem=nil)
    @xml_elem = elem
    @internal_instance = nil
  end
end

def build_id_table(doc)
  table = {}
  doc.root.each_recursive do |elem|
    id = elem.attributes['id']
    table[id] = ElementData.new(elem) if id != nil
  end
  table
end

def read_url(elem, attr_name)
  url = elem.attributes[attr_name]
  if url == nil or url.empty? or url[0] != "#" or url.length == 1
    raise "missing or incorrectly formatted '#{attr_name}' attribute"
    nil
  else
    url[1..-1]
  end
end

def read_matrix(matrix_elem)
  array = matrix_elem.text.to_s.split.map {|str_val| Float(str_val)}
  if array.count != 16
    raise "incorrectly formatted <matrix> element"
  end
  [array[0...4], array[4...8], array[8...12], array[12...16]]
end

def read_node(node_elem, id_table)
  node = Node.new
  id = node_elem.attributes['id']
  if id != nil
    node.id = id
    id_table[id].internal_instance = node
  end
  node_elem.elements.each('node') do |child_node_elem|
    node.child_nodes << read_node(child_node_elem, id_table)
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
    raise "more than one <matrix> element in a node. unsupported for now."
  end
  matrix_elem = node_elem.elements['matrix']
  node.transform = read_matrix(matrix_elem) if matrix_elem != nil
  node
end

# returns a list of Nodes
def read_nodes(elem, id_table)
  return [] if elem == nil
  nodes = []
  elem.elements.each('node') do |node_elem|
    nodes << read_node(node_elem, id_table)
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

  def initialize
    @vertex_format = nil
    @vertices = []
    @indices = []
  end
end

def read_triangles_inputs(triangles_elem)
  inputs = {}
  triangles_elem.elements.each('input') do |input_elem|
    semantic = input_elem.attributes['semantic']
    raise "missing semantic attr on <input>" if semantic == nil
    source = read_url(input_elem, 'source')
    offset_str = input_elem.attributes['offset']
    raise "missing offset attr on <input>" if offset == nil
    offset = Integer(offset_str)
    set_str = input_elem.attributes['set']
    set = set_str == nil ? 0 : Integer(set_str)

    hash_val = {:source => source, :offset => offset}
    inputs[:vertex] = hash_val if semantic.upcase == "VERTEX" and inputs[:vertex] == nil
    inputs[:normal] = hash_val if semantic.upcase == "NORMAL" and inputs[:normal] == nil
    inputs[:texcoord] = hash_val if semantic.upcase == "TEXCOORD" and set == 0 and inputs[:texcoord] == nil
  end
  raise "missing <input> with semantic=VERTEX" if inputs[:vertex] == nil
  inputs
end

def get_vertices_position_source(vertices_id, id_table)
  vertices_elem = id_table[vertices_id]
  raise "couldn't find <vertices> element with id=#{vertices_id}" if !vertices_elem
  vertices_elem.elements.each('input') do |input_elem|
    semantic = input_elem.attributes['semantic']
    if semantic != nil and semantic.upcase == "POSITION"
      return read_url(input_elem, 'source')
    end
  end
  raise "couldn't read <input> with semantic=POSITION from <vertices>"
end

def get_triangles_index_stride(triangles_elem)
  max_offset = -1
  triangles_elem.each('input') do |input_elem|
    offset_str = input_elem.attributes['offset']
    if offset_str
      offset = Integer(offset_str)
      max_offset = [max_offset, offset].max
    end
  end
  max_offset + 1
end

# returns an array of arrays, where each sub-array is a position, normal, or tex coord
def read_source(source_id, id_table, *expected_param_names)
  source_elem = id_table[source_id]
  raise "couldn't find <source> element with id=#{source_id}" if !source_elem
  technique_common_elem = source_elem.elements['technique_common']
  raise "missing <technique_common> element in <source>" if !technique_common_elem
  accessor_elem = technique_common_elem.elements['accessor']
  raise "missing <accessor> element in <technique_common>" if !accessor_elem
  param_names = []
  accessor_elem.elements.each('param') do |param_elem|
    param_name = param_elem.attributes['name']
    param_type = param_elem.attributes['type']
    raise "<param> element missing 'name' attr" if param_name == nil
    raise "<param> element missing 'type' attr" if param_type == nil
    raise "<param>s with type=#{param_type} are not supported" if param_type != "float"
    param_names << param_name.upcase
  end
  expected_param_names = expected_param_names.map {|name| name.upcase}
  if expected_param_names != param_names
    raise "got unexpected params #{param_names} in <accessor>"
  end
  
  []
end

# returns a Mesh
def read_triangles(triangles_elem, id_table)
  inputs = read_triangles_inputs(triangles_elem)
  position_source = get_vertices_position_source(inputs[:vertex][:source])
  inputs[:position] = inputs[:vertex].clone
  inputs[:position][:source] = position_source

  positions = read_source(inputs[:position][:source], id_table)
  normals = inputs[:normal] ? read_source(inputs[:normal][:source], id_table) : nil
  texcoords = inputs[:texcoord] ? read_source(inputs[:texcoord][:source], id_table) : nil

  index_stride = get_triangles_index_stride(triangles_elem)

  Mesh.new
end

# returns a Mesh array
def read_geometry(geom_elem, id_table)
  mesh_elem = geom_elem.elements['mesh']
  raise "missing <mesh> element in <geometry>" if !mesh_elem
  meshes = []
  mesh_elem.elements.each('triangles') do |triangles_elem|
    meshes << read_triangles(triangles_elem)
  end
  id = geom_elem.attributes['id']
  id_table[id].internal_instance = meshes if id != nil
  meshes
end

# main
doc = REXML::Document.new(File.open('model.dae'))
id_table = build_id_table(doc)
scene_nodes = read_nodes(doc.elements['/COLLADA/library_visual_scenes/visual_scene'], id_table)
