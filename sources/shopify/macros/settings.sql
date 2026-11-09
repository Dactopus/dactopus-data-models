{# The settings guard of the incremental models: the same file in every
   package (tests/check_contracts.py). The package's dbt_project.yml runs it
   on all its models, +pre-hook "{{ dactopus_check_settings() }}" and
   +post-hook "{{ dactopus_save_settings() }}", ahead of a model's own hooks
   in dbt v1 and v2; on a model that is not incremental both do nothing.

   The variables the rows already built depend on are meta.guarded_vars in
   that file, each with its default in vars: a change of one leaves an
   incremental run rebuilding the rows it rereads by the new value and
   keeping the rest by the old one, and no test fails. meta.free_vars are
   the variables any run may change. A table built whole, or by a full
   refresh, records the guarded values in its comment; an incremental run
   that finds other values stops before a hook or the model reads or
   deletes a row, and names them. A full refresh builds the table anew and
   records the new values.

   The record is the comment's last segment, "built with <JSON>", keys in
   alphabetical order. A package may keep segments of its own before it,
   joined by "; ", and saving keeps them. #}

{# The guarded variables, {name: default}, from meta.guarded_vars. #}
{% macro dactopus_guarded_vars() -%}
{{- return((config.get('meta') or {}).get('guarded_vars') or {}) -}}
{%- endmacro %}

{# Whether the guard acts on this model: an incremental one, at run time. #}
{% macro dactopus_guards() -%}
{{- return(execute and config.get('materialized') == 'incremental') -}}
{%- endmacro %}

{# The guarded variables with their values in this run. #}
{% macro dactopus_settings() -%}
{%- set settings = {} -%}
{%- for name in dactopus_guarded_vars() -%}
{%- do settings.update({name: var(name)}) -%}
{%- endfor -%}
{{- return(settings) -}}
{%- endmacro %}

{# The JSON of the table's record, '' without one. #}
{% macro dactopus_recorded_settings() -%}
{%- set r = run_query("SELECT extract(comment, '(?:^|; )built with (.*)$') FROM system.tables WHERE database = '"
                      ~ this.schema ~ "' AND name = '" ~ this.identifier ~ "'") -%}
{{- return(r.columns[0].values()[0] if r.columns[0].values() else '') -}}
{%- endmacro %}

{# A setting's value in the form the check compares: a list sorted, with
   its items as strings (the order of excluded statuses means nothing),
   a dict with its values as strings, a scalar as a string (a value given
   as "2" is the 2 the table recorded). #}
{% macro dactopus_setting_value(value) -%}
{%- if value is mapping -%}
{%- set d = {} -%}
{%- for k, v in value.items() -%}{%- do d.update({k | string: v | string}) -%}{%- endfor -%}
{{- return(d) -}}
{%- elif value is iterable and value is not string -%}
{{- return(value | map('string') | sort | list) -}}
{%- else -%}
{{- return(value | string) -}}
{%- endif -%}
{%- endmacro %}

{# Pre-hook: stops an incremental run whose table was built with other
   values of the guarded variables than this run has, or that records
   none. A variable the record lacks was guarded by a later release than
   the one that built the table, which built it with the variable's
   default: the release that starts guarding a variable keeps its default
   to what the earlier release did. Only a deployment that sets another
   value then builds anew. #}
{% macro dactopus_check_settings() -%}
{%- if dactopus_guards() and not dactopus_guarded_vars() -%}
{{ exceptions.raise_compiler_error(this ~ " is incremental, and meta.guarded_vars names no variable: the package's dbt_project.yml lists them, and a project that installs the package must not replace its meta") }}
{%- endif -%}
{%- if dactopus_guards() and is_incremental() -%}
{%- set defaults = dactopus_guarded_vars() -%}
{%- set recorded = dactopus_recorded_settings() -%}
{%- set built = fromjson(recorded, none) if recorded else none -%}
{%- set differ = [] -%}
{%- if built is mapping -%}
{%- for name, value in dactopus_settings().items() -%}
{%- set was = built[name] if name in built else defaults[name] -%}
{%- if dactopus_setting_value(was) != dactopus_setting_value(value) -%}
{%- do differ.append(name ~ " was " ~ tojson(was) ~ ", is " ~ tojson(value)) -%}
{%- endif -%}
{%- endfor -%}
{%- else -%}
{%- do differ.append("it records no settings this release reads: a release before this one built it, or its comment was changed by hand") -%}
{%- endif -%}
{%- if differ -%}
{{ exceptions.raise_compiler_error(this ~ " was not built with the settings of this run (" ~ differ | join("; ") ~ "): run dbt build --full-refresh once (package README, Changing a setting)") }}
{%- endif -%}
{%- endif -%}
SELECT 1
{%- endmacro %}

{# Post-hook: a table just built, whole or by a full refresh, records the
   values it was built with. An incremental run changes nothing: its
   pre-hook has found them the same. is_incremental() cannot tell a first
   build here: the table exists by now, and dbt v2 answers true where v1
   answers false (a full refresh: false in both). The two signs are
   should_full_refresh() and a table that records nothing. #}
{% macro dactopus_save_settings() -%}
{%- if dactopus_guards() and (should_full_refresh() or not dactopus_recorded_settings()) -%}
{%- set kept = run_query("SELECT replaceRegexpOne(comment, '(?:^|; )built with .*$', '') FROM system.tables WHERE database = '"
                         ~ this.schema ~ "' AND name = '" ~ this.identifier ~ "'").columns[0].values()[0] -%}
{%- set record = "built with " ~ tojson(dactopus_settings(), sort_keys=true) -%}
ALTER TABLE {{ this }} MODIFY COMMENT '{{ ((kept ~ "; " if kept else "") ~ record) | replace('\\', '\\\\') | replace("'", "\\'") }}'
{%- else -%}
SELECT 1
{%- endif -%}
{%- endmacro %}
