# frozen_string_literal: true

require "digest"
require "pathname"

class CoachZed
  module Catalog
    class Entry
      attr_reader :path, :relative_path, :title, :domain, :session_duration, :precedence, :frequency, :program, :format, :equipment, :summary, :work_items, :notes, :source_urls

      def initialize(
        path:,
        relative_path:,
        title:,
        summary:,
        work_items:,
        notes:,
        source_urls:,
        domain: nil,
        session_duration: nil,
        precedence: nil,
        frequency: nil,
        program: nil,
        format: nil,
        equipment: nil
      )
        @path = path
        @relative_path = relative_path
        @title = title
        @domain = domain
        @session_duration = session_duration
        @precedence = precedence
        @frequency = frequency
        @program = program
        @format = format
        @equipment = equipment
        @summary = summary
        @work_items = work_items
        @notes = notes
        @source_urls = source_urls
      end

      def fingerprint
        Digest::SHA256.hexdigest([
          relative_path,
          title,
          domain,
          session_duration,
          precedence,
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
          "precedence" => precedence,
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

        # @type var metadata: Hash[String, String]
        metadata = {}
        index = 1
        index += 1 while index < lines.length && lines[index].strip.empty?
        while index < lines.length
          line = lines[index]
          break if line.nil? || line.empty?
          break unless line.start_with?("- ")

          if (match = line.match(/^- ([^:]+):\s*(.*)$/))
            key = normalize_key(match[1].to_s)
            metadata[key] = strip_ticks(match[2].to_s)
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
          precedence: metadata["precedence"],
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
        # @type var sections: Hash[String, Array[String]]
        sections = {}
        current = nil

        lines.each do |line|
          if (match = line.match(/^##\s+(.+)$/))
            current = normalize_section_name(match[1].to_s)
            next
          end

          next unless current
          section_name = current.to_s

          sections[section_name] ||= []
          sections[section_name] << line
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
