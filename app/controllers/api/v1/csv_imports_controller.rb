class Api::V1::CsvImportsController < Api::V1::BaseController
  expose(:csv_import)
  expose(:csv_imports)
  
  def create
    csv_import.save
    respond_with(:api, csv_import)
  end

  def update
    csv_import.save
    respond_with(:api, csv_import)
  end
end
