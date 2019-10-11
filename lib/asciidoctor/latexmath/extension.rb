# frozen_string_literal: true

require 'pathname'
require 'asciidoctor/extensions'
require 'http'
require 'pry'

autoload :Digest, 'digest'

class Asciidoctor::Latexmath::Treeprocessor < Asciidoctor::Extensions::Treeprocessor
  LineFeed = %(\n)
  StemInlineMacroRx = /\\?(?:stem|latexmath):([a-z,]*)\[(.*?[^\\])\]/m.freeze
  LatexmathInlineMacroRx = /\\?latexmath:([a-z,]*)\[(.*?[^\\])\]/m.freeze

  def process(document)
    http = HTTP.persistent('http://localhost:8080')

    output_dir = fetch_output_dir(document)
    ::Asciidoctor::Helpers.mkdir_p(output_dir) unless ::File.directory?(output_dir)

    stem_blocks = document.find_by(context: :stem) || []
    stem_blocks.each do |stem|
      path = render_expression(http, stem.content, output_dir)
      next unless path

      parent = stem.parent
      index  = parent.blocks.index(stem)
      attrs  = { 'target' => path, 'alt' => "($$#{stem.content}$$)", 'align' => 'center' }

      image       = create_image_block(parent, attrs)
      image.id    = stem.id if stem.id
      image.title = stem.attributes['title'] if stem.attributes['title']

      parent.blocks[index] = image
    end

    nil
  end

  def render_expression(http, exp, output_dir)
    content = http.get('/', params: { exp: CGI.unescapeHTML(exp) }).to_s
    return if content.empty?

    path = ::File.join(output_dir, "stem-#{::Digest::MD5.hexdigest(exp)}.svg")
    ::IO.write path, content
    path
  rescue StandardError
    nil
  end

  def fetch_output_dir(parent)
    document   = parent.document
    base_dir   = parent.attr('outdir') || (document.respond_to?(:options) && document.options[:to_dir])
    output_dir = parent.attr('imagesdir')

    parent.normalize_system_path(output_dir, base_dir)
  end
end
