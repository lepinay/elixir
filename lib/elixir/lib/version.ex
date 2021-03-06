defmodule Version do
  @moduledoc ~S"""
  Functions for parsing and matching versions against requirements.

  A version is a string in a specific format or a `Version`
  generated after parsing via `Version.parse/1`.

  `Version` parsing and requirements follow
  [SemVer 2.0 schema](http://semver.org/).

  ## Versions

  In a nutshell, a version is given by three numbers:

      MAJOR.MINOR.PATCH

  Pre-releases are supported by appending `-[0-9A-Za-z-\.]`:

      "1.0.0-alpha.3"

  Build information can be added by appending `+[0-9A-Za-z-\.]`:

      "1.0.0-alpha.3+20130417140000"

  ## Struct

  The version is represented by the Version struct and it has its
  fields named according to Semver: `:major`, `:minor`, `:patch`,
  `:pre` and `:build`.

  ## Requirements

  Requirements allow you to specify which versions of a given
  dependency you are willing to work against. It supports common
  operators like `>=`, `<=`, `>`, `==` and friends that
  work as one would expect:

      # Only version 2.0.0
      "== 2.0.0"

      # Anything later than 2.0.0
      "> 2.0.0"

  Requirements also support `and` and `or` for complex conditions:

      # 2.0.0 and later until 2.1.0
      ">= 2.0.0 and < 2.1.0"

  Since the example above is such a common requirement, it can
  be expressed as:

      "~> 2.0.0"

  """

  import Kernel, except: [match?: 2]
  defstruct [:major, :minor, :patch, :pre, :build]

  @type version     :: String.t | t
  @type requirement :: String.t | Version.Requirement.t
  @type matchable   :: {major :: String.t | non_neg_integer,
                        minor :: non_neg_integer | nil,
                        patch :: non_neg_integer | nil,
                        pre   :: [String.t]}

  defmodule Requirement do
    @moduledoc false
    defstruct [:source, :matchspec]
  end

  defexception InvalidRequirement, [:message]
  defexception InvalidVersion, [:message]

  @doc """
  Check if the given version matches the specification.

  Returns `true` if `version` satisfies `requirement`, `false` otherwise.
  Raises a `Version.InvalidRequirement` exception if `requirement` is not
  parseable, or `Version.InvalidVersion` if `version` is not parseable.
  If given an already parsed version and requirement this function won't
  raise.

  ## Examples

      iex> Version.match?("2.0.0", ">1.0.0")
      true

      iex> Version.match?("2.0.0", "==1.0.0")
      false

      iex> Version.match?("foo", "==1.0.0")
      ** (Version.InvalidVersion) foo

      iex> Version.match?("2.0.0", "== ==1.0.0")
      ** (Version.InvalidRequirement) == ==1.0.0

  """
  @spec match?(version, requirement) :: boolean
  def match?(vsn, req) when is_binary(req) do
    case parse_requirement(req) do
      {:ok, req} ->
        match?(vsn, req)
      :error ->
        raise InvalidRequirement, message: req
    end
  end

  def match?(version, %Requirement{matchspec: spec}) do
    {:ok, result} = :ets.test_ms(to_matchable(version), spec)
    result != false
  end

  @doc """
  Compares two versions. Returns `:gt` if first version is greater than
  the second and `:lt` for vice versa. If the two versions are equal `:eq`
  is returned

  Raises a `Version.InvalidVersion` exception if `version` is not parseable.
  If given an already parsed version this function won't raise.

  ## Examples

      iex> Version.compare("2.0.1-alpha1", "2.0.0")
      :gt

      iex> Version.compare("2.0.1+build0", "2.0.1")
      :eq

      iex> Version.compare("invalid", "2.0.1")
      ** (Version.InvalidVersion) invalid

  """
  @spec compare(version, version) :: :gt | :eq | :lt
  def compare(vsn1, vsn2) do
    do_compare(to_matchable(vsn1), to_matchable(vsn2))
  end

  defp do_compare({major1, minor1, patch1, pre1}, {major2, minor2, patch2, pre2}) do
    cond do
      {major1, minor1, patch1} > {major2, minor2, patch2} -> :gt
      {major1, minor1, patch1} < {major2, minor2, patch2} -> :lt
      pre1 == [] and pre2 != [] -> :gt
      pre1 != [] and pre2 == [] -> :lt
      pre1 > pre2 -> :gt
      pre1 < pre2 -> :lt
      true -> :eq
    end
  end

  @doc """
  Parse a version string into a `Version`.

  ## Examples

      iex> Version.parse("2.0.1-alpha1") |> elem(1)
      #Version<2.0.1-alpha1>

      iex> Version.parse("2.0-alpha1")
      :error

  """
  @spec parse(String.t) :: {:ok, t} | :error
  def parse(string) when is_binary(string) do
    case Version.Parser.parse_version(string) do
      {:ok, {major, minor, patch, pre}} ->
        vsn = %Version{major: major, minor: minor, patch: patch,
                       pre: pre, build: get_build(string)}
        {:ok, vsn}
     :error ->
       :error
    end
  end

  @doc """
  Parse a version requirement string into a `Version.Requirement`.

  ## Examples

      iex> Version.parse_requirement("== 2.0.1") |> elem(1)
      #Version.Requirement<== 2.0.1>

      iex> Version.parse_requirement("== == 2.0.1")
      :error

  """
  @spec parse_requirement(String.t) :: {:ok, Requirement.t} | :error
  def parse_requirement(string) when is_binary(string) do
    case Version.Parser.parse_requirement(string) do
      {:ok, spec} ->
        {:ok, %Requirement{source: string, matchspec: spec}}
      :error ->
        :error
    end
  end

  defp to_matchable(%Version{major: major, minor: minor, patch: patch, pre: pre}) do
    {major, minor, patch, pre}
  end

  defp to_matchable(string) do
    case Version.Parser.parse_version(string) do
      {:ok, vsn} -> vsn
      :error -> raise InvalidVersion, message: string
    end
  end

  defp get_build(string) do
    case Regex.run(~r/\+([^\s]+)$/, string) do
      nil ->
        nil

      [_, build] ->
        build
    end
  end

  defmodule Parser.DSL do
    @moduledoc false

    defmacro deflexer(match, do: body) when is_binary(match) do
      quote do
        def lexer(unquote(match) <> rest, acc) do
          lexer(rest, [unquote(body) | acc])
        end
      end
    end

    defmacro deflexer(acc, do: body) do
      quote do
        def lexer("", unquote(acc)) do
          unquote(body)
        end
      end
    end

    defmacro deflexer(char, acc, do: body) do
      quote do
        def lexer(<< unquote(char) :: utf8, rest :: binary >>, unquote(acc)) do
          unquote(char) = << unquote(char) :: utf8 >>

          lexer(rest, unquote(body))
        end
      end
    end
  end

  defmodule Parser do
    @moduledoc false
    import Parser.DSL

    deflexer ">=",    do: :'>='
    deflexer "<=",    do: :'<='
    deflexer "~>",    do: :'~>'
    deflexer ">",     do: :'>'
    deflexer "<",     do: :'<'
    deflexer "==",    do: :'=='
    deflexer "!=",    do: :'!='
    deflexer "!",     do: :'!='
    deflexer " or ",  do: :'||'
    deflexer " and ", do: :'&&'
    deflexer " ",     do: :' '

    deflexer x, [] do
      [x, :'==']
    end

    deflexer x, [h | acc] do
      cond do
        is_binary h ->
          [h <> x | acc]

        h in [:'||', :'&&'] ->
          [x, :'==', h | acc]

        true ->
          [x, h | acc]
      end
    end

    deflexer acc do
      Enum.filter(Enum.reverse(acc), &(&1 != :' '))
    end

    @version_regex ~r/^
      (\d+)                 # major
      (?:\.(\d+))?          # minor
      (?:\.(\d+))?          # patch
      (?:\-([\d\w\.\-]+))?  # pre
      (?:\+([\d\w\-]+))?    # build
      $/x

    @spec parse_requirement(String.t) :: {:ok, Version.Requirement.t} | :error
    def parse_requirement(source) do
      lexed = lexer(source, [])
      to_matchspec(lexed)
    end

    defp nillify(""), do: nil
    defp nillify(o),  do: o

    @spec parse_version(String.t) :: {:ok, Version.matchable} | :error
    def parse_version(string, approximate? \\ false) when is_binary(string) do
      if parsed = Regex.run(@version_regex, string) do
        destructure [_, major, minor, patch, pre], parsed
        patch = nillify(patch)
        pre   = nillify(pre)

        if nil?(minor) or (nil?(patch) and not approximate?) do
          :error
        else
          major = binary_to_integer(major)
          minor = binary_to_integer(minor)
          patch = patch && binary_to_integer(patch)

          case parse_pre(pre) do
            {:ok, pre} ->
              {:ok, {major, minor, patch, pre}}
            :error ->
              :error
          end
        end
      else
        :error
      end
    end

    defp parse_pre(nil), do: {:ok, []}
    defp parse_pre(pre), do: parse_pre(String.split(pre, "."), [])

    defp parse_pre([piece|t], acc) do
      cond do
        piece =~ ~r/^(0|[1-9][0-9]*)$/ ->
          parse_pre(t, [binary_to_integer(piece)|acc])
        piece =~ ~r/^[0-9]*$/ ->
          :error
        true ->
          parse_pre(t, [piece|acc])
      end
    end

    defp parse_pre([], acc) do
      {:ok, Enum.reverse(acc)}
    end

    defp valid_requirement?([]), do: false
    defp valid_requirement?([a | next]), do: valid_requirement?(a, next)

    # it must finish with a version
    defp valid_requirement?(a, []) when is_binary(a) do
      true
    end

    # or <op> | and <op>
    defp valid_requirement?(a, [b | next]) when is_atom(a) and is_atom(b) and a in [:'||', :'&&'] do
      valid_requirement?(b, next)
    end

    # <version> or | <version> and
    defp valid_requirement?(a, [b | next]) when is_binary(a) and is_atom(b) and b in [:'||', :'&&'] do
      valid_requirement?(b, next)
    end

    # or <version> | and <version>
    defp valid_requirement?(a, [b | next]) when is_atom(a) and is_binary(b) and a in [:'||', :'&&'] do
      valid_requirement?(b, next)
    end

    # <op> <version>
    defp valid_requirement?(a, [b | next]) when is_atom(a) and is_binary(b) do
      valid_requirement?(b, next)
    end

    defp valid_requirement?(_, _) do
      false
    end

    defp approximate_upper(version) do
      case version do
        {major, _minor, nil, _} ->
          {major + 1, 0, 0, [0]}

        {major, minor, _patch, _} ->
          {major, minor + 1, 0, [0]}
      end
    end

    defp to_matchspec(lexed) do
      if valid_requirement?(lexed) do
        first = to_condition(lexed)
        rest  = Enum.drop(lexed, 2)
        {:ok, [{{:'$1', :'$2', :'$3', :'$4'}, [to_condition(first, rest)], [:'$_']}]}
      else
        :error
      end
    catch
      :invalid_matchspec -> :error
    end

    defp to_condition([:'==', version | _]) do
      version = parse_condition(version)
      {:'==', :'$_', {:const, version}}
    end

    defp to_condition([:'!=', version | _]) do
      version = parse_condition(version)
      {:'/=', :'$_', {:const, version}}
    end

    defp to_condition([:'~>', version | _]) do
      from = parse_condition(version, true)
      to   = approximate_upper(from)

      {:andalso, to_condition([:'>=', matchable_to_string(from)]),
                 to_condition([:'<', matchable_to_string(to)])}
    end

    defp to_condition([:'>', version | _]) do
      {major, minor, patch, pre} = parse_condition(version)

      {:orelse, {:'>', {{:'$1', :'$2', :'$3'}},
                       {:const, {major, minor, patch}}},
                {:andalso, {:'==', {{:'$1', :'$2', :'$3'}},
                                        {:const, {major, minor, patch}}},
                {:orelse, {:andalso, {:'==', {:length, :'$4'}, 0},
                                     {:'/=', length(pre), 0}},
                          {:andalso, {:'/=', length(pre), 0},
                                     {:orelse, {:'>', {:length, :'$4'}, length(pre)},
                                     {:andalso, {:'==', {:length, :'$4'}, length(pre)},
                                                {:'>', :'$4', {:const, pre}}}}}}}}
    end

    defp to_condition([:'>=', version | _]) do
      matchable = parse_condition(version)

      {:orelse, {:'==', :'$_', {:const, matchable}},
                to_condition([:'>', version])}
    end

    defp to_condition([:'<', version | _]) do
      {major, minor, patch, pre} = parse_condition(version)

      {:orelse, {:'<', {{:'$1', :'$2', :'$3'}},
                       {:const, {major, minor, patch}}},
                {:andalso, {:'==', {{:'$1', :'$2', :'$3'}},
                                   {:const, {major, minor, patch}}},
                {:orelse, {:andalso, {:'/=', {:length, :'$4'}, 0},
                                     {:'==', length(pre), 0}},
                          {:andalso, {:'/=', {:length, :'$4'}, 0},
                          {:orelse, {:'<', {:length, :'$4'}, length(pre)},
                                    {:andalso, {:'==', {:length, :'$4'}, length(pre)},
                                               {:'<', :'$4', {:const, pre}}}}}}}}
    end

    defp to_condition([:'<=', version | _]) do
      matchable = parse_condition(version)

      {:orelse, {:'==', :'$_', {:const, matchable}},
                to_condition([:'<', version])}
    end

    defp to_condition(current, []) do
      current
    end

    defp to_condition(current, [:'&&', operator, version | rest]) do
      to_condition({:andalso, current, to_condition([operator, version])}, rest)
    end

    defp to_condition(current, [:'||', operator, version | rest]) do
      to_condition({:orelse, current, to_condition([operator, version])}, rest)
    end

    defp parse_condition(version, approximate? \\ false) do
      case parse_version(version, approximate?) do
        {:ok, version} -> version
        :error -> throw :invalid_matchspec
      end
    end

    defp matchable_to_string({major, minor, patch, pre}) do
      patch = if patch, do: "#{patch}", else: "0"
      pre   = if pre != [], do: "-#{Enum.join(pre, ".")}"
      "#{major}.#{minor}.#{patch}#{pre}"
    end
  end
end

defimpl String.Chars, for: Version do
  def to_string(version) do
    pre = unless Enum.empty?(pre = version.pre), do: "-#{pre}"
    build = if build = version.build, do: "+#{build}"
    "#{version.major}.#{version.minor}.#{version.patch}#{pre}#{build}"
  end
end

defimpl Inspect, for: Version do
  def inspect(self, _opts) do
    "#Version<" <> to_string(self) <> ">"
  end
end

defimpl String.Chars, for: Version.Requirement do
  def to_string(%Version.Requirement{source: source}) do
    source
  end
end

defimpl Inspect, for: Version.Requirement do
  def inspect(%Version.Requirement{source: source}, _opts) do
    "#Version.Requirement<" <> source <> ">"
  end
end
