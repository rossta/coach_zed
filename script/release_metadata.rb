#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"

options = {
  output_dir: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: script/release_metadata.rb --output-dir PATH"

  opts.on("--output-dir PATH", "Directory to write release metadata into") do |value|
    options[:output_dir] = value
  end
end.parse!

abort("Provide --output-dir") if options[:output_dir].nil?

output_dir = File.expand_path(options[:output_dir])
FileUtils.mkdir_p(output_dir)

version = nil
version_candidates = [
  %w[git-mkver],
  %w[git-mkver version],
  %w[git-mkver next],
  %w[git-mkver next-version]
]

version_candidates.each do |candidate|
  stdout, status = Open3.capture2e(*candidate)
  next unless status.success?

  match = stdout.match(/\b\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\b/)
  next unless match

  version = match[0]
  break
end

abort("Unable to determine the next release version with git-mkver") if version.nil?

notes = nil
notes_candidates = [
  %w[git-mkver changelog],
  %w[git-mkver release-notes],
  %w[git-mkver notes],
  %w[git-mkver --changelog]
]

notes_candidates.each do |candidate|
  stdout, status = Open3.capture2e(*candidate)
  next unless status.success?

  stripped = stdout.to_s.strip
  next if stripped.empty?

  notes = stripped
  break
end

abort("Unable to generate release notes with git-mkver") if notes.nil?

File.write(File.join(output_dir, "version.txt"), "#{version}\n")
File.write(File.join(output_dir, "release-notes.md"), "#{notes}\n")
