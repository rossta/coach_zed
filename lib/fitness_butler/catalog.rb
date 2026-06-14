# frozen_string_literal: true

require "digest"
require "pathname"

class FitnessButler
  module Catalog
    Entry = Struct.new(
      :path,
      :relative_path,
      :title,
      :domain,
      :session_duration,
      :frequency,
      :program,
      :format,
      :equipment,
      :summary,
      :work_items,
      :notes,
      :source_urls,
      keyword_init: true
    ) do
      def fingerprint
        Digest::SHA256.hexdigest([
          relative_path,
          title,
          domain,
          session_duration,
          frequency,
          program,
          format,
          equipment,
          summary,
          work_items.join("\n"),
          notes.join("\n"),
          source_urls.join("\n")
        ].join("\u0000"))
      end

      def to_h
        {
          "path" => path.to_s,
          "relative_path" => relative_path,
          "title" => title,
          "domain" => domain,
          "session_duration" => session_duration,
          "frequency" => frequency,
          "program" => program,
          "format" => format,
          "equipment" => equipment,
          "summary" => summary,
          "work_items" => work_items,
          "notes" => notes,
          "source_urls" => source_urls
        }
      end
    end

    class Loader
      IGNORED_BASENAMES = %w[INDEX.md TEMPLATE.md].freeze

      def initialize(root)
        @root = Pathname(root)
      end

      def load
        Dir.glob(@root.join("**/*.md")).sort.filter_map do |file|
          path = Pathname(file)
          next if ignored?(path)

          parse_entry(path)
        end
      end

      private

      attr_reader :root

      def ignored?(path)
        IGNORED_BASENAMES.include?(path.basename.to_s)
      end

      def parse_entry(path)
        relative_path = path.relative_path_from(root).to_s
        lines = path.read.lines(chomp: true)
        title = lines.find { |line| line.start_with?("# ") }&.sub("# ", "")
        return if title.nil?

        metadata = {}
        index = 1
        index += 1 while index < lines.length && lines[index].strip.empty?
        while index < lines.length
          line = lines[index]
          break if line.nil? || line.empty?
          break unless line.start_with?("- ")

          if (match = line.match(/^- ([^:]+):\s*(.*)$/))
            key = normalize_key(match[1])
            metadata[key] = strip_ticks(match[2])
          end

          index += 1
        end

        index += 1 while index < lines.length && lines[index].strip.empty?

        sections = parse_sections(lines[index..] || [])

        Entry.new(
          path: path,
          relative_path: relative_path,
          title: title,
          domain: metadata["domain"],
          session_duration: metadata["session_duration"],
          frequency: metadata["frequency"],
          program: metadata["program"],
          format: metadata["format"],
          equipment: metadata["equipment"],
          summary: sections.fetch("summary", []).join(" ").strip,
          work_items: normalize_bullets(sections.fetch("work", [])),
          notes: normalize_bullets(sections.fetch("notes", [])),
          source_urls: normalize_urls(sections.fetch("source", []))
        )
      end

      def parse_sections(lines)
        sections = Hash.new { |hash, key| hash[key] = [] }
        current = nil

        lines.each do |line|
          if (match = line.match(/^##\s+(.+)$/))
            current = normalize_section_name(match[1])
            next
          end

          sections[current] << line if current
        end

        sections
      end

      def normalize_section_name(name)
        name.downcase.strip
      end

      def normalize_key(key)
        key.downcase.tr(" -", "_")
      end

      def strip_ticks(value)
        value.to_s.delete_prefix("`").delete_suffix("`")
      end

      def normalize_bullets(lines)
        lines.filter_map do |line|
          next if line.strip.empty?

          line.sub(/^- /, "").strip
        end
      end

      def normalize_urls(lines)
        lines.filter_map do |line|
          next unless line.match?(%r{\A-\s+https?://})

          line.sub(/^- /, "")
        end
      end
    end
  end
end
