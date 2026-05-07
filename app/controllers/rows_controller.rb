class RowsController < ApplicationController
  def bushes
    row = Row.find(params[:id])
    bushes = row.bushes.order(:bush_number).map do |bush|
      {
        id: bush.id,
        bush_number: bush.bush_number
      }
    end
    render json: bushes
  end
end
