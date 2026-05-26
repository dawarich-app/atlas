defmodule Atlas.Maps.Upstream.Client do
  defmodule Unavailable do
    defexception [:message, :upstream]
  end

  defmodule BadResponse do
    defexception [:message, :upstream, :status]
  end

  def build(base_url, opts \\ []) do
    Req.new(
      base_url: base_url,
      connect_options: [timeout: Keyword.get(opts, :open_timeout, 2_000)],
      receive_timeout: Keyword.get(opts, :timeout, 5_000),
      retry: false,
      decode_json: [keys: :strings]
    )
  end

  def get(req, path, params \\ []) do
    case Req.get(req, url: path, params: params) do
      {:ok, %{status: s, body: body}} when s in 200..299 ->
        {:ok, body}

      {:ok, %{status: s}} ->
        {:error, %BadResponse{message: "#{s} from #{req.options[:base_url]}#{path}", status: s}}

      {:error, exception} ->
        {:error, %Unavailable{message: Exception.message(exception)}}
    end
  end

  def post(req, path, body) do
    case Req.post(req, url: path, json: body) do
      {:ok, %{status: s, body: response_body}} when s in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: s}} ->
        {:error, %BadResponse{message: "#{s} from #{req.options[:base_url]}#{path}", status: s}}

      {:error, exception} ->
        {:error, %Unavailable{message: Exception.message(exception)}}
    end
  end
end
