// OUT-001: sample bilingual slides (English primary, Vietnamese secondary). Original short lines; Amazing Grace is public domain.
import Domain

enum SampleSlides {
    static let all: [SlideContent] = [
        SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay, tiếng ca sao ngọt ngào"),
        SlideContent(primary: "That saved a wretch like me", secondary: "Đã cứu một người tội lỗi như tôi"),
        SlideContent(primary: "I once was lost, but now am found", secondary: "Xưa tôi lạc lối, nay được tìm thấy"),
        SlideContent(primary: "Was blind, but now I see", secondary: "Xưa tôi mù lòa, nay được thấy sáng"),
        SlideContent(primary: "Praise the Lord, all you nations", secondary: "Hãy ngợi khen Chúa, hỡi muôn dân"),
        SlideContent(primary: "Stacked marks: Ễ Ậ Ở Ỗ Ẵ ỷ ự", secondary: "Nguyện xin Chúa ban phước, ễ ậ ở ỗ ẵ"),
    ]
}
