# fluent-plugin-redmine

## Overview

Output fplugin for [Fluentd](http://fluentd.org). Create and regist a ticket to redmine from messages.

## Installation

Install with `gem`, `fluent-gem` or `td-agent-gem` command as:

```
# for system installed fluentd
$ gem install fluent-plugin-redmine

# for td-agent
$ sudo /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-redmine

# for td-agent2
$ sudo td-agent-gem install fluent-plugin-redmine
```

## Usage

In your fluentd configration, use `@type redmine`.

Here is example settings:

    @type redmine
    url http://localhost:3000/
    api_key 40a96d43a98b1626c542b04c5780f881c1e1a969
    tracker_id 1
    priority_id 3
    subject The new issue %{issue}
    description This is the new issue called %{name}. we cought new exception %{error}!


and here is optional configuration:

    project_id  myproject              # projectId of redmine
    category_id 70                     # categoryId of tickets
    project_id_key key_of_priority_id  # value in record for priorityId
    category_id_key key_of_category_id # value in record for categoryId
    tag_key my_ tag                    # 'tag' is used by default
    debug_http  true                   # set debug_http=true of Net::HTTP module, false is used by default


### placeholders

You can look values in records by using `%{hoge}` for subject and description. If you specify *tag_key* in configuration, you can also look tag value by `%{your_specified_tag_key}`.

## TODO

Pull requests are very welcome!!
