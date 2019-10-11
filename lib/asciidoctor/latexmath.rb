# frozen_string_literal: true

require 'asciidoctor/latexmath/version'
require 'asciidoctor/latexmath/extension'

module Asciidoctor
  module Latexmath
    class Error < StandardError; end
  end
end

Asciidoctor::Extensions.register do
  treeprocessor Asciidoctor::Latexmath::Treeprocessor
end
