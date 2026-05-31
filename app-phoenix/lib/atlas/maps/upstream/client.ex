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
      connect_options: [
        timeout: Keyword.get(opts, :open_timeout, 2_000),
        protocols: [:http1]
      ],
      receive_timeout: Keyword.get(opts, :timeout, 5_000),
      retry: &retry_only_pool/2,
      max_retries: 2,
      retry_delay: 10,
      decode_json: [keys: :strings]
    )
  end

  @doc """
  Build a client from `<PREFIX>_URL` / `<PREFIX>_TIMEOUT` / `<PREFIX>_OPEN_TIMEOUT`
  env vars. `default_url` is used when `<PREFIX>_URL` is unset.

      Client.build_from_env("PHOTON", "http://localhost:8001",
                            timeout: 5_000, open_timeout: 2_000)
  """
  def build_from_env(prefix, default_url, defaults \\ []) do
    base_url = System.get_env("#{prefix}_URL") || default_url
    timeout = env_int("#{prefix}_TIMEOUT", Keyword.get(defaults, :timeout, 5_000))
    open_timeout = env_int("#{prefix}_OPEN_TIMEOUT", Keyword.get(defaults, :open_timeout, 2_000))
    build(base_url, timeout: timeout, open_timeout: open_timeout)
  end

  @doc "Read an integer env var, falling back to `default` when unset."
  def env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  # Retry only on Finch pool exhaustion. All other errors (connect refused,
  # 5xx, etc.) fail fast so Bypass-down tests stay quick.
  defp retry_only_pool(_req, %Req.HTTPError{reason: :pool_not_available}), do: true
  defp retry_only_pool(_req, _other), do: false

  def get(req, path, params \\ []) do
    case Req.get(req, url: path, params: params) do
      {:ok, %{status: s, body: body}} when s in 200..299 ->
        {:ok, maybe_decode(body)}

      {:ok, %{status: s}} ->
        {:error, %BadResponse{message: "#{s} from #{req.options[:base_url]}#{path}", status: s}}

      {:error, exception} ->
        {:error, %Unavailable{message: Exception.message(exception)}}
    end
  end

  def post(req, path, body) do
    case Req.post(req, url: path, json: body) do
      {:ok, %{status: s, body: response_body}} when s in 200..299 ->
        {:ok, maybe_decode(response_body)}

      {:ok, %{status: s}} ->
        {:error, %BadResponse{message: "#{s} from #{req.options[:base_url]}#{path}", status: s}}

      {:error, exception} ->
        {:error, %Unavailable{message: Exception.message(exception)}}
    end
  end

  def post_raw(req, path, body, content_type \\ "text/plain") do
    case Req.post(req, url: path, body: body, headers: [{"content-type", content_type}]) do
      {:ok, %{status: s, body: response_body}} when s in 200..299 ->
        {:ok, maybe_decode(response_body)}

      {:ok, %{status: s}} ->
        {:error, %BadResponse{message: "#{s} from #{req.options[:base_url]}#{path}", status: s}}

      {:error, exception} ->
        {:error, %Unavailable{message: Exception.message(exception)}}
    end
  end

  defp maybe_decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> body
    end
  end

  defp maybe_decode(body), do: body
end
