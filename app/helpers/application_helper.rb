module ApplicationHelper
  def nav_buttons
    capture do
      concat(
        link_to("javascript:history.back()", class: "p-[10px] rounded-[12px] hover:bg-[white] hidden", id: "back-button", title: "Назад") do
          image_tag "/back.png", alt: "Back", class: "w-8 h-8"
        end
      )
      concat(
        link_to("javascript:history.forward()", class: "p-[10px] rounded-[12px] hover:bg-[white] hidden", id: "forward-button", title: "Вперёд") do
          image_tag "/back.png", alt: "Forward", class: "w-8 h-8 rotate-180"
        end
      )
      if @parent_id.present?
        concat(
          link_to(folder_path(@parent_id), class: "p-[10px] rounded-[12px] hover:bg-[white]", title: "Вверх") do
            image_tag "/back.png", alt: "Forward", class: "w-8 h-8 rotate-90"
          end
        )
      end
    end
  end

  def ru_pluralize(*args)
    case args.length
    when 4
      # ru_pluralize(5, "папка", "папки", "папок")
      one, few, many = args[1], args[2], args[3]
      count = args[0].to_i
      remainder10 = count % 10
      remainder100 = count % 100

      if remainder100.between?(11, 14)
        "#{count} #{many}"
      elsif remainder10 == 1
        "#{count} #{one}"
      elsif remainder10.between?(2, 4)
        "#{count} #{few}"
      else
        "#{count} #{many}"
      end
    when 5
      count1 = args[0].to_i
      count2 = args[1].to_i
      if count1 == 1 && count2 == 0
        args[2]
      elsif count1 == 0 && count2 == 1
        args[3]
      else
        args[4]
      end
    end
  end
end
