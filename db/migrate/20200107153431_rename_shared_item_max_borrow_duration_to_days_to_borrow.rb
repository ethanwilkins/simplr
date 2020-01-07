class RenameSharedItemMaxBorrowDurationToDaysToBorrow < ActiveRecord::Migration[6.0]
  def change
    rename_column :shared_items, :max_borrow_duration, :days_to_borrow
    change_column :shared_items, :days_to_borrow, :integer, "USING days_to_borrow::integer"
  end
end
