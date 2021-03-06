defmodule BlueBird.Writer.Blueprint do
  @moduledoc """
  Defines functions to generate an API BluePrint representation of the
  `BlueBird.ApiDoc` struct.
  """
  import BlueBird.Writer, only: [group_routes: 2]

  alias BlueBird.{ApiDoc, JSONData, Parameter, Request, Response, Route}

  @doc """
  Generates a string from an `BlueBird.ApiDocs{}` struct.
  """
  @spec generate_output(ApiDoc.t()) :: String.t()
  def generate_output(docs) do
    doc_routes =
      docs.routes
      |> group_routes(:group)
      |> Enum.sort_by(&first_char(elem(&1, 0)))
      |> Enum.map(fn {group_name, routes} -> {beautify(group_name), routes} end)
      |> process_groups(docs.groups)

    print_metadata(docs.host) <>
      "\n" <> print_overview(docs) <> "\n\n" <> doc_routes
  end

  ## Groups

  @spec process_groups([{String.t(), [Route.t()]}], map) :: String.t()
  defp process_groups(groups, groups_map) do
    Enum.map_join(groups, "\n", &process_group(&1, groups_map))
  end

  @spec process_group({String.t() | nil, [Route.t()]}, map) :: String.t()
  defp process_group({nil, routes}, _) do
    routes
    |> group_routes(:resource)
    |> Enum.sort_by(&first_char(elem(&1, 0)))
    |> process_resources
  end

  defp process_group({group_name, routes}, groups_map) do
    grouped_routes =
      routes
      |> group_routes(:resource)
      |> Enum.sort_by(&first_char(elem(&1, 0)))

    "# Group #{beautify(group_name)}\n\n" <>
      group_description(Map.get(groups_map, group_name, "")) <>
      process_resources(grouped_routes)
  end

  @spec beautify(atom() | String.t() | any()) :: atom() | String.t() | any()
  def beautify(val) when is_atom(val) do
    val
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> Macro.camelize()
  end

  def beautify(val) when is_binary(val) do
    val
    |> String.replace("_", " ")
    |> Macro.camelize()
  end

  def beautify(val) do
    val
  end

  @spec group_description(String.t()) :: String.t()
  defp group_description(""), do: ""
  defp group_description(description), do: "#{description}\n\n"

  ## Resources

  @spec process_resources([
          {String.t(), [{String.t(), String.t(), [Route.t()]}]}
        ]) :: String.t()
  defp process_resources(resources) do
    Enum.map_join(resources, "\n", &process_resource(&1))
  end

  @spec process_resource({String.t() | nil, [Route.t()]}) :: String.t()
  defp process_resource({_path, routes}) do
    optional_parameters = find_optional_parameters(routes)
    resource_id = find_resource_id(routes)

    random_route = Enum.random(routes)

    path =
      random_route.path
      |> strip_resource_id_if_set()
      |> append_clean_resource_id(resource_id)
      |> replace_path_params()
      |> inject_optional_parameters(optional_parameters)

    "## #{beautify(random_route.resource)} [#{path}]\n\n" <>
      process_routes(routes)
  end

  @resource_id_regex ~r/:([\w]+)$/

  defp strip_resource_id_if_set(path) do
    Regex.replace(@resource_id_regex, path, "")
  end

  defp append_clean_resource_id(path, resource_id)
       when is_binary(resource_id) do
    sep =
      case String.ends_with?(path, "/") do
        true -> ""
        false -> "/"
      end

    path <> sep <> resource_id
  end

  defp append_clean_resource_id(path, _) do
    path
  end

  def find_resource_id(routes) when is_list(routes) do
    routes
    |> Enum.flat_map(&find_resource_id/1)
    |> Enum.uniq()
    |> List.first()
  end

  def find_resource_id(route) do
    result = Regex.run(@resource_id_regex, route.path, capture: :first)

    result || []
  end

  defp find_optional_parameters(routes) when is_list(routes) do
    Enum.flat_map(routes, &find_optional_parameters/1)
  end

  defp find_optional_parameters(route) do
    route.parameters
    |> Enum.filter(& &1.optional)
    |> Enum.map(& &1.name)
  end

  ## Routes

  @doc false
  @spec process_routes([Route.t()]) :: String.t()
  def process_routes(routes) do
    routes
    |> Enum.sort_by(&{&1.path, &1.method})
    |> Enum.map_join("\n", &process_route(&1))
  end

  @doc false
  @spec process_route(Route.t()) :: String.t()
  def process_route(route) do
    [
      print_route_definition(route),
      print_note(route.note),
      print_warning(route.warning),
      route.parameters |> process_parameters(),
      route.requests |> process_requests()
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  ## Parameters

  @spec process_parameters([Parameter.t()]) :: String.t()
  defp process_parameters([_ | _] = parameters) do
    "+ Parameters\n\n" <> parameter_list(parameters)
  end

  defp process_parameters(_), do: ""

  @spec parameter_list([Parameter.t()]) :: String.t()
  defp parameter_list(parameters) do
    parameters
    |> Enum.map_join("\n", &process_parameter(&1))
    |> indent(4)
  end

  defp fields_list(fields) do
    fields
    |> Enum.map_join("\n", &process_field(&1))
    |> indent(4)
  end

  defp process_field(field) do
    [
      print_field_main(field),
      field.additional_desc |> print_param_additional_desc() |> indent(4),
      field.default |> print_param_default() |> indent(4),
      field.members |> print_param_members() |> indent(4)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp print_field_main(field) do
    "- #{field.name}#{example_to_string(field.example)} " <>
      "(#{field.type}, #{optional_to_str(field.optional)})" <>
      description_to_str(field.description) <> "\n"
  end

  @spec process_parameter(Parameter.t()) :: String.t()
  defp process_parameter(param) do
    [
      print_param_main(param),
      param.additional_desc |> print_param_additional_desc() |> indent(4),
      param.default |> print_param_default() |> indent(4),
      param.members |> print_param_members() |> indent(4)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  ## Requests

  @spec process_requests([Request.t()]) :: String.t()
  defp process_requests([_ | _] = requests) do
    requests
    |> Enum.sort_by(& &1.response.status)
    |> Enum.map_join("\n", &process_conn(&1))
  end

  defp process_requests(_), do: ""

  @spec process_conn(Request.t()) :: String.t()
  defp process_conn(request) do
    process_request(request) <> process_response(request)
  end

  defp process_request(request) do
    content_type = get_content_type(request.headers)

    req_str =
      [
        request.headers |> filter_headers() |> print_headers() |> indent(4),
        request.body_params |> print_attributes |> indent(4),
        request.body_params |> print_body_params |> indent(4)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    if req_str == "" && content_type == "" do
      ""
    else
      request_title =
        request_title(request.response.status, content_type, request.name)

      "+ Request #{request_title} \n\n" <> req_str <> "\n"
    end
  end

  ## Responses

  @spec process_response(Request.t()) :: String.t()
  defp process_response(request) do
    response = request.response
    content_type = get_content_type(response.headers)
    status = response.status
    request_title = request_title(status, content_type, request.name)

    [
      "+ Response #{status} #{content_type} \n",
      response.headers |> filter_headers() |> print_headers() |> indent(4),
      response.body |> print_body() |> indent(4)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec request_title(integer(), String.t(), String.t()) :: String.t()
  defp request_title(status, content_type, nil = _name) do
    "#{status}#{content_type}"
  end

  defp request_title(status, content_type, name) do
    "#{name}#{content_type}"
  end

  @spec get_content_type([{String.t(), String.t()}]) :: String.t()
  defp get_content_type([_ | _] = headers) do
    case Enum.find(headers, fn {key, _} -> key == "content-type" end) do
      {_, value} -> " (#{value})"
      _ -> ""
    end
  end

  defp get_content_type(_), do: ""

  ## Frontmatter

  @doc false
  @spec print_metadata(String.t()) :: String.t()
  def print_metadata(host), do: "FORMAT: 1A\nHOST: #{host}\n"

  @doc false
  @spec print_overview(ApiDoc.t()) :: String.t()
  def print_overview(api_doc) do
    "# #{api_doc.title}\n" <>
      print_description(api_doc.description) <>
      print_tos(api_doc.terms_of_service) <>
      print_contact(api_doc.contact) <> print_license(api_doc.license)
  end

  @spec print_description(String.t()) :: String.t()
  defp print_description(""), do: ""
  defp print_description(description), do: "#{description}\n"

  @spec print_tos(String.t()) :: String.t()
  defp print_tos(""), do: ""
  defp print_tos(tos), do: "\n## Terms of Service\n#{tos}\n"

  @spec print_contact(name: String.t(), url: String.t(), email: String.t()) ::
          String.t()
  defp print_contact(name: "", url: "", email: ""), do: ""

  defp print_contact(contact) do
    "\n## Contact\n" <>
      print_if_set(contact[:name]) <>
      print_if_set(contact[:url] |> print_link) <>
      print_if_set(contact[:email] |> print_email)
  end

  @spec print_license(name: String.t(), url: String.t()) :: String.t()
  defp print_license(name: "", url: ""), do: ""

  defp print_license(license) do
    "\n## License\n" <>
      print_if_set(license[:name]) <> print_if_set(license[:url] |> print_link)
  end

  @spec print_if_set(String.t()) :: String.t()
  defp print_if_set(""), do: ""
  defp print_if_set(line), do: "#{line}\n"

  @spec print_link(String.t()) :: String.t()
  defp print_link(""), do: ""
  defp print_link(link), do: "[#{link}](#{link})"

  @spec print_email(String.t()) :: String.t()
  defp print_email(""), do: ""
  defp print_email(email), do: "[#{email}](mailto:#{email})"

  ## Route Definition

  @spec print_route_definition(Route.t()) :: String.t()
  defp print_route_definition(route) do
    print_route_header(route.method, route.title) <>
      print_route_description(route.description) <>
      print_route_fields(route.fields)
  end

  defp inject_optional_parameters(path, parameters) when is_list(parameters) do
    if Enum.empty?(parameters) do
      path
    else
      path <> "{?#{Enum.join(parameters, ",")}}"
    end
  end

  defp inject_optional_parameters(path, _) do
    path
  end

  @spec print_route_header(String.t(), String.t() | nil) :: String.t()
  defp print_route_header(method, nil), do: "### #{beautify(method)}\n"

  defp print_route_header(method, title) do
    "### #{beautify(title)} [#{method}]\n"
  end

  @spec print_route_description(String.t() | nil) :: String.t()
  defp print_route_description(nil), do: ""
  defp print_route_description(description), do: "#{description}\n"

  @spec print_route_fields(list() | nil) :: String.t()
  defp print_route_fields(fields) when is_list(fields) do
    if Enum.empty?(fields) do
      ""
    else
      "\n\n" <> fields_list(fields)
    end
  end

  defp print_route_fields(_) do
    ""
  end

  ## Attributes

  @spec print_attributes(map) :: String.t()
  def print_attributes(attributes) when attributes == %{}, do: ""

  def print_attributes(attributes) do
    "+ Attributes (object)\n\n" <> walk_through_attributes(attributes)
  end

  @spec print_attribute({String.t(), any}) :: String.t()
  defp print_attribute({key, value}) when is_map(value) do
    print_attribute_name_and_type(key, value) <>
      walk_through_attributes(value, 4)
  end

  defp print_attribute({key, value}) when is_list(value) do
    if is_map(List.first(value)) do
      print_attribute_name_and_type(key, value) <>
        ("+ (object)\n" |> indent(4)) <>
        walk_through_attributes(List.first(value))
    else
      print_attribute_name_and_type(key, value)
    end
  end

  defp print_attribute({key, value}) do
    print_attribute_name_and_type(key, value)
  end

  @spec print_attribute_name_and_type(String.t(), any) :: String.t()
  defp print_attribute_name_and_type(key, value) do
    "+ #{key} (#{JSONData.type(value)})\n"
  end

  @spec walk_through_attributes(map, number) :: String.t()
  defp walk_through_attributes(attributes, indent \\ 8) do
    attributes
    |> Enum.map_join(&print_attribute(&1))
    |> indent(indent)
  end

  ## Parameters

  @spec print_param_main(Parameter.t()) :: String.t()
  defp print_param_main(param) do
    "+ #{param.name}#{example_to_string(param.example)} " <>
      "(#{param.type}, #{optional_to_str(param.optional)})" <>
      description_to_str(param.description) <> "\n"
  end

  @spec example_to_string(String.t() | nil) :: String.t()
  defp example_to_string(nil), do: ""
  defp example_to_string(example), do: ": #{example}"

  @spec optional_to_str(boolean) :: String.t()
  defp optional_to_str(true), do: "optional"
  defp optional_to_str(_), do: "required"

  @spec description_to_str(String.t() | nil) :: String.t()
  defp description_to_str(nil), do: ""
  defp description_to_str(description), do: " - #{description}"

  @spec print_param_additional_desc(String.t() | nil) :: String.t()
  defp print_param_additional_desc(nil), do: ""
  defp print_param_additional_desc(desc), do: "#{desc}\n"

  @spec print_param_default(String.t() | nil) :: String.t()
  defp print_param_default(nil), do: ""
  defp print_param_default(default), do: "+ Default: #{default}\n"

  @spec print_param_members([String.t()] | nil) :: String.t()
  defp print_param_members([_ | _] = members) do
    "+ Members\n" <> (members |> Enum.map_join(&"+ #{&1}\n") |> indent(4))
  end

  defp print_param_members(_), do: ""

  ## Notes and Warnings

  @spec print_note(String.t() | nil) :: String.t()
  defp print_note(nil), do: ""

  defp print_note(note) do
    "::: note\n#{note}\n:::\n"
  end

  @spec print_warning(String.t() | nil) :: String.t()
  defp print_warning(nil), do: ""

  defp print_warning(warning) do
    "::: warning\n#{warning}\n:::\n"
  end

  ## Headers

  @doc false
  @spec print_headers([{String.t(), String.t()}]) :: String.t()
  def print_headers([_ | _] = headers) do
    "+ Headers\n\n" <>
      (headers |> Enum.map_join(&print_header(&1)) |> indent(8))
  end

  def print_headers(_), do: ""

  @spec print_header({String.t(), String.t()}) :: String.t()
  defp print_header({key, value}) do
    "#{key}: #{value}\n"
  end

  @spec filter_headers([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  defp filter_headers([_ | _] = headers) do
    Enum.reject(headers, fn {key, _} -> key == "content-type" end)
  end

  defp filter_headers(_), do: []

  ## Body

  @spec print_body(String.t() | nil) :: String.t()
  defp print_body(body) when is_nil(body) or body == "", do: ""

  defp print_body(body) do
    "+ Body\n\n" <> (body |> indent(8)) <> "\n"
  end

  @spec print_body_params(map) :: String.t()
  defp print_body_params(body) when body == %{}, do: ""
  defp print_body_params(body), do: body |> Jason.encode!() |> print_body()

  @spec indent(String.t(), integer) :: String.t()
  defp indent(str, count) do
    str
    |> String.split("\n")
    |> Enum.map(fn line ->
      case line do
        "" -> ""
        s -> String.duplicate(" ", count) <> s
      end
    end)
    |> Enum.join("\n")
  end

  @spec display_path(Route.t()) :: String.t()
  defp display_path(route) do
    route.path
    |> replace_path_params()
    |> add_query_params(route.requests)
  end

  @spec replace_path_params(String.t()) :: String.t()
  defp replace_path_params(path) do
    ~r/:([\w]+)(\/|\z)/
    |> Regex.replace(path, "{\\1}/")
    |> String.trim_trailing("/")
  end

  @spec add_query_params(String.t(), [Request.t()]) :: String.t()
  defp add_query_params(path, []), do: path

  defp add_query_params(path, requests) do
    case get_query_param_str(requests) do
      "" -> path
      params -> "#{path}{?#{params}}"
    end
  end

  @spec get_query_param_str([Request.t()]) :: String.t()
  defp get_query_param_str(requests) do
    requests
    |> Enum.reduce(%{}, fn request, params ->
      Map.merge(params, request.query_params)
    end)
    |> Map.keys()
    |> Enum.map(&to_string(&1))
    |> Enum.join(",")
  end

  defp first_char(at) when is_atom(at) do
    at
    |> Atom.to_string()
    |> first_char()
  end
  defp first_char(str) when is_binary(str) do
    str
    |> String.at(0)
    |> String.downcase()
  end
  defp first_char(_) do
    false
  end
end
