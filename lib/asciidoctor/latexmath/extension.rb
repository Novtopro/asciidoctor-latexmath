# frozen_string_literal: true

require 'pathname'
require 'asciidoctor/extensions'
require 'http'
require 'english'

autoload :Digest, 'digest'

class Asciidoctor::Latexmath::Treeprocessor < Asciidoctor::Extensions::Treeprocessor
  LineFeed = %(\n)
  StemInlineMacroRx = /\\?(?:stem|latexmath):([a-z,]*)\[(.*?[^\\])\]/m.freeze

  def process(document)
    url = document.attr('latexmath-url')
    return unless url

    http = HTTP.persistent(url)

    output_dir = fetch_output_dir(document)
    ::Asciidoctor::Helpers.mkdir_p(output_dir) unless ::File.directory?(output_dir)

    process_stems(document, http, output_dir)
    process_proses(document, http, output_dir)
    process_sections(document, http, output_dir)
    process_tables(document, http, output_dir)

    nil
  end

  def process_stems(document, http, output_dir)
    blocks = document.find_by(context: :stem) || []

    blocks.each do |stem|
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
  end

  def process_proses(document, http, output_dir)
    blocks = document.find_by do |it|
      list_item      = (it.context == :list_item)
      include_macros = (it.content_model == :simple && it.subs.include?(:macros) && it.context != :table_cell)

      list_item || include_macros
    end || []

    blocks.each do |it|
      text           = it.context == :list_item ? it.instance_variable_get(:@text).to_s : (it.lines * LineFeed).to_s
      sanitized_text = sanitize(http, output_dir, text)

      next if text == sanitized_text

      if it.context == :list_item
        it.instance_variable_set :@text, sanitized_text
      else
        it.lines = sanitized_text.split(LineFeed)
      end
    end
  end

  def process_tables(document, http, output_dir)
    blocks = document.find_by(context: :table) || []

    blocks.each do |it|
      rows = it.rows[:body] + it.rows[:foot]
      rows.each do |row|
        row.each do |cell|
          if cell.style == :asciidoc
            process(row.inner_document)
            next
          end

          next unless cell.style != :literal

          text           = cell.instance_variable_get(:@text).to_s
          sanitized_text = sanitize(http, output_dir, text)

          next if text == sanitized_text

          cell.instance_variable_set :@text, sanitized_text
        end
      end
    end
  end

  def process_sections(document, http, output_dir)
    blocks = document.find_by(content: :section) || []

    blocks.each do |it|
      text           = it.instance_variable_get(:@title).to_s
      sanitized_text = sanitize(http, output_dir, text)

      next if text == sanitized_text

      it.instance_variable_set :@title, sanitized_text
      it.remove_instance_variable :@converted_title
    end
  end

  def render_expression(http, exp, output_dir)
    content = http.get('/', params: { exp: CGI.unescapeHTML(exp) }).to_s
    return if content.empty?

    path = ::File.join(output_dir, "stem-#{::Digest::MD5.hexdigest(exp)}.svg")
    ::IO.write path, content
    path
  end

  def fetch_output_dir(parent)
    document   = parent.document
    base_dir   = parent.attr('outdir') || (document.respond_to?(:options) && document.options[:to_dir])
    output_dir = parent.attr('imagesdir')

    parent.normalize_system_path(output_dir, base_dir)
  end

  def sanitize(http, output_dir, text)
    text.gsub(StemInlineMacroRx) do
      match = $LAST_MATCH_INFO

      exp  = match[2]
      path = render_expression(http, exp, output_dir)

      "image:#{path}[role=inline-latexmath]"
    end
  end
end
