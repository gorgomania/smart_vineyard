class RowsController < ApplicationController
  def bushes
    row = Row.find(params[:id])
    authorize row

    bushes = row.bushes.order(:bush_number).map do |bush|
      {
        id: bush.id,
        bush_number: bush.bush_number
      }
    end
    render json: bushes
  end
end
