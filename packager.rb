#!/usr/bin/env ruby

# Copyright (c) 2009 A Different Engine LLC
# 
# Please email any issues/bugs to bugs@adifferentengine.com
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so.
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# This is a widget packager file it's here in order to package this app easily
# for distribution. run packager.rb -h for docs it requires ruby to be installed
# but a base install is fine, it shouldn't require any gems.


require 'optparse'
require 'fileutils'
require 'find'
require 'rexml/document'

include REXML

$options = {}

# Edit here to add more supported resolutions
$resolution_sizes = ['960x540', '1920x1080']
# 2.5 MB for small 5 for large
$max_sizes =        {'960x540' => 2621440, '1920x1080' => 5242880 }
$path_to_widget_xml ="/Contents/widget.xml"
$ignore_files = []



def main
  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: packager.rb [options] widgetpath"
    $options[:verbose] = false
    $options[:ignore_file_given]  = false
    $options[:size] = false
    $options[:output_dir] = "packager_output"
  
    opts.on('-v', '--verbose', 'Output more information') do
      $options[:verbose] = true
    end
  
    opts.on('-s','--size', 'Package for a particular size.  Will only delete .js file and directories named after resolutions that are not the size given') do |size|
      $options[:size] = size
    end
    
  
    opts.on('-i', '--ignore-file FILE', 'Text file with list of files to ignore in packaging. One file per line, accepts wildcards for directories.  Will also look for a file called .ignore in the root directory') do |ignore|
      $options[:ignore] = ignore
      $options[:ignore_file_given] = true
    end
  
    opts.on('-h','--help', 'Display this screen') do
      puts "\n\nPackaging script for Yahoo Widgets, will copy all files to /tmp then package for the different sizes and put the resulting zip files in a directory called #{$options[:output_dir]}/[size].\n\nWill remove directories under image/ that don't match the size paramter and any .js files that are named after a size other then the given parameter (so when packaging for 960x540 anything named 1920x1080.js will be deleted).\n\nThe current resoltions supported are [#{$resolution_sizes.join(', ')}]\n\n"
      puts opts
      exit
    end
    
    opts.on('-o', '--outfile FILE', 'Output Filename. If not specified we\'ll parse the widget.xml file to get id and version information and create the filename from that') do |outfile|
      $options[:outfile] = outfile
    end
    
    opts.on('-d', '--outputdir DIR', 'Output directory, default is ./packager_output') do |odir|
      odir.chop! if odir =~ /\/$/
      $options[:output_dir] = odir
    end
  end
  # First parse the options
  optparse.parse!

  # find the root directory
  
  
  # Clean up user input - no trailing slashes
  directory = ARGV.first || '.'
  directory.strip!
  directory = File.expand_path(directory)
  directory.chop! if directory =~ /\/$/
  
  current_dir = File.expand_path(File.dirname(directory)) 
  current_dir = current_dir + "/" unless current_dir =~ /\/$/
  
  # Add this file if we're in the widget directory
  this_file = File.expand_path(__FILE__)
  this_file.slice!(current_dir.length, this_file.length) if(this_file.index(current_dir) == 0 )
  ignore_files = [this_file]
  
  # Validate Input
  display "Validating user input"
  abort "#{directory} is not a widget directory " unless File.extname(directory) == '.widget'
  abort "Invalid size given #{$options[:size]}" unless $resolution_sizes
  abort "Can't find Contents Directory" unless File.directory? "#{directory}/Contents"  
  abort "Can't find widget.xml file" unless File.exists?("#{directory}#{$path_to_widget_xml}")
  
  # if the ignore file is absolute we'll use that, if not we'll be relative to root widget directory,
  path_to_ignore_file = $options[:ignore]
  path_to_ignore_file = directory +"/"+ path_to_ignore_file unless $options[:ignore] =~ /^\//

  if $options[:ignore_file_given]
    abort "Can't find ignore file: #{path_to_ignore_file}" unless File.exists?(path_to_ignore_file)
  end
  
  display "Trying with ignore file: #{path_to_ignore_file}"
  if(File.exists?(path_to_ignore_file))
    ig_file = File.open(path_to_ignore_file)
    ig_file.each_line do |f|
      f.strip!
      $ignore_files.push f unless (f =~ /^\#/ || f.empty?)
    end
  end
  
  unless $options[:outfile]
    display "Reading widget.xml for output filename"
    doc = REXML::Document.new File.read("#{directory}#{$path_to_widget_xml}") 
    id = XPath.first(doc, "/metadata/identifier")
    version = XPath.first(doc, "metadata/version")
    abort "Can't find id in widget.xml file" unless id
    abort "Can't find version in widget.xml file" unless version
    $options[:outfile] = "#{id.text}-#{version.text}.widget"
  end
  
  # Cleanup any current packager output (maybe I don't want to do this?  It can make subversion wonky)
  FileUtils.rm_r($options[:output_dir]) if File.directory?($options[:output_dir])
  
  if $options[:size]
    package_for_size(directory, $options[:size], $options[:outfile])
  else
    $resolution_sizes.each {|size| package_for_size directory, size, $options[:outfile] }
  end
  exit
end

def package_for_size(directory, size, outfile)
  puts "\nCreating packaged widget for: #{size}"
  base_dir_name = File.basename(directory)
  temp_dir = "/tmp/Widget.#{Time.now.to_i}"
  working_dir = "#{temp_dir}/#{File.basename(directory)}"
  
  # Copy to temp
  
  display "Creating temp directory #{temp_dir}"
  FileUtils.mkdir("#{temp_dir}", :mode => 0777, :verbose => $options[:verbose])
  
  display "Copying file to temp dir"
  FileUtils.cp_r(directory, working_dir, :verbose => $options[:verbose])
  

  display "Cleaning up files"
  Find.find(working_dir) do |path|
    filename = File.split(path)[1]
    
    # Remove hidden files
    if File.basename(path)[0] == ?.
      display "Removing: #{path}"
      FileUtils.rm_r(path) 
    end
    
    # Remove bad sized files
    if(size)
      bad_sizes = $resolution_sizes.reject {|t| t == size}
      if(( FileTest.directory?(path) && bad_sizes.include?(filename)) || bad_sizes.map{|f| "#{f}.js"}.include?(File.basename(path)))
        display "Removing: #{path}, Current size: #{size}"
        FileUtils.rm_r(path)
      end
    end
    
    # Remove ignore files
    if !$ignore_files.empty? && $ignore_files.map{|f| "#{working_dir}/#{f}"}.include?(path)
      display "Ignoring: #{path}"
      FileUtils.rm_r(path) 
    end
  end
  
  
  # Zip the file
  zoptions =  '-r'
  zoptions = "#{zoptions} -q" unless $options[:verbose]
  
  # Can't seem to find an argument to zip the file with a relative path in the source zip
  # This is a bit hacky but works, could have used a ruby zip library - but didn't want to require gems
  cmd = "cd #{temp_dir}; zip #{zoptions} #{$options[:outfile]} #{base_dir_name};cd - > /dev/null"
  display "Running: #{cmd}"
  
  # Gives a warning about world writable directories, I probably shouldn't suppress
  $VERBOSE = $options[:verbose] || nil
  system cmd
  # Should turn back on regardless of user option
  $VERBOSE = true

  FileUtils.mkdir_p("#{$options[:output_dir]}/#{size}/")
  
  final_zip = "#{$options[:output_dir]}/#{size}/#{$options[:outfile]}"
  
  FileUtils.cp_r("#{temp_dir}/#{$options[:outfile]}",final_zip )
  
  display "Cleaning up temp directory"
  FileUtils.rm_r(temp_dir)
  
  
  
  puts "Created: #{final_zip}\nFile size: #{prettyBytes(File.size(final_zip),2)} - size is #{File.size(final_zip) <= $max_sizes[size] ? 'ok' : 'OVER!'}\n"
end

def display(string)
  puts " #{string}" if $options[:verbose] 
end

def prettyBytes(bytes, precision = 1)
  bytes = bytes.to_f
  case 
    when bytes < 1024; "%d #{Format.plural(bytes, 'byte', 'bytes')}" % bytes
    when bytes < 1048576; "%.#{precision}f KB" % (bytes / 1024)
    when bytes < 1073741824; "%.#{precision}f MB" % (bytes / 1048576)
    when bytes >= 1073741824; "%.#{precision}f GB" % (bytes / 1073741824)
  end
end



main

