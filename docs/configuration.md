---
title: Configuration Language - logstash
layout: content_right
---
# LogStash Config Language

The logstash config language aims to be simple.

There's 3 main sections: inputs, filters, outputs. Each section has
configurations for each plugin available in that section.

Example:

    # This is a comment. You should use comments to describe
    # parts of your configuration.
    input {
      ...
    }

    filter {
      ...
    }

    output {
      ...
    }

## Filters and Ordering

For a given event, are applied in the order of appearance in the config file.

## Comments

Comments are as in ruby, perl, and python. Starts with a '#' character. Example:

    # this is a comment

    input { # comments can appear at the end of a line, too
      # ...
    }

## Plugins

The input, filter, and output sections all let you configure plugins. Plugins
configuration consists of the plugin name followed by a block of settings for
that plugin. For example, how about two file inputs:

    input {
      file {
        path => "/var/log/messages"
        type => "syslog"
      }

      file {
        path => "/var/log/apache/access.log"
        type => "apache"
      }
    }

The above configures a two file inputs. Both set two config settings each:
path and type. Each plugin has different settings for configuring it, seek the
documentation for your plugin to learn what settings are available and what they mean. For example, the [file input][fileinput] documentation will explain the meanings of the path and type settings.

[fileinput]: inputs/file

## Value Types

The documentation for a plugin may say that a config field has a certain type.
Examples include boolean, string, array, number, map, etc.

### <a name="boolean"></a>Boolean

A boolean must be either true or false. Quoted or unquoted doesn't matter.

Examples:

    debug => true
    enabled => false

### <a name="string"></a>String

A string must be a single value.

Example:

    name => "Hello world"

Single, unquoted words are valid as strings, too, but you should use quotes for
consistency.

### <a name="number"></a>Number

Numbers can be whole number or decimal values (100, 40.43, etc)

Example:

    port => 33
    delay => 0.100

### <a name="array"></a>Array

An 'array' can be a single string value or multiple. If you specify the same
attribute multiple times, it appends to the array.

Examples:

    input {
      file {
        path => [ "/var/log/messages", "/var/log/*.log" ]
        path => "/data/mysql/mysql.log"
      }
   }

The above makes 'path' a 3-element array including all 3 strings.

### <a name="Map"></a>Map

A map is a way to set key+value pairs. As an example, the mutate filter has an
attribute 'rename' that takes a map for its value.

    filter {
      mutate {
        rename => { "oldname" => "newname" }
      }
    }

If you are familiar with Perl or Ruby's hash syntax, this is the same.

## Further Reading

For more information, see [the plugin docs index](index)

