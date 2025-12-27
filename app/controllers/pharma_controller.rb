class PharmaController < ApplicationController
  def status
    # Exec your existing script
    output = `bin/check_pharma.sh`
    render json: { raw_output: output, parsed: parse_pharma_output(output) }
  end
end
