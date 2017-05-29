defmodule BlueBird.Test.Support.Examples.RouteTitles do
  @moduledoc false

  alias BlueBird.{ApiDoc, Request, Response, Route}

  def api_doc do
    %ApiDoc{
      title: "Heavenly API",
      host: "https://youarguelikeaninformer.socrates",
      routes: [
        %Route{
          method: "GET",
          title: "Ride",
          path: "/route-with-title",
          group: "Pony",
          requests: [%Request{
            response: %Response{
              status: 204,
              headers: [],
              body: ""
            }
          }]
        },
        %Route{
          method: "GET",
          path: "/route-without-title",
          group: "Pony",
          requests: [%Request{
            response: %Response{
              status: 204,
              headers: [],
              body: ""
            }
          }]
        },
      ]
    }
  end

  def output do
    """
    FORMAT: 1A
    HOST: https://youarguelikeaninformer.socrates

    # Heavenly API


    # Group Pony

    ## Ride [GET /route-with-title]

    + Response 204

    ## GET /route-without-title

    + Response 204
    """
  end
end
