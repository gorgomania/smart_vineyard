module ApplicationHelper
  def nav_buttons
    capture do
      concat(
        link_to("javascript:history.back()", class: "p-[10px] rounded-[12px] hover:bg-[white] hidden", id: "back-button") do
          image_tag "http://localhost:3000/back.png", alt: "Back", class: "w-8 h-8"
        end
      )
      concat(
        link_to("javascript:history.forward()", class: "p-[10px] rounded-[12px] hover:bg-[white] hidden", id: "forward-button") do
          image_tag "http://localhost:3000/back.png", alt: "Forward", class: "w-8 h-8 rotate-180"
        end
      )
      if @parent_id.present?
        concat(
          link_to(folder_path(@parent_id), class: "p-[10px] rounded-[12px] hover:bg-[white]") do
            image_tag "http://localhost:3000/back.png", alt: "Forward", class: "w-8 h-8 rotate-90"
          end
        )
      end
    end
  end
end
